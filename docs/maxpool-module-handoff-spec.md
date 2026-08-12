# INT8 2×2 MaxPool Tile RTL 모듈 제작 요청서

## 1. 문서 목적

이 문서는 PYNQ-Z2용 YOLOv3-Tiny CNN 가속기에 연결할 **signed INT8 2×2
MaxPool 타일 하위 모듈**의 제작 규격이다. 제작자는 이 문서만으로 RTL,
테스트벤치, 합성 검증을 완료할 수 있어야 한다.

모듈은 한 입력 채널의 row-major INT8 타일 stream을 받아 2×2 maximum pooling을
수행한다. YOLOv3-Tiny에 필요한 stride 2와 stride 1을 모두 지원한다.

```text
INT32 tile accumulator
→ activation
→ INT8 requantization
→ [이 문서의 MaxPool 모듈]
→ INT8 packer/output FIFO
→ AXI DMA S2MM
```

MaxPool은 채널 간 값을 섞지 않는다. 입력 채널마다 독립적으로 같은 연산을
수행하며, 채널 및 공간 타일 반복은 PS 또는 상위 scheduler가 담당한다.

대상 환경은 다음과 같다.

| 항목 | 값 |
| --- | --- |
| FPGA | Xilinx XC7Z020-1 (`xc7z020clg400-1`) |
| 보드 | TUL PYNQ-Z2 |
| 도구 | Vivado 2024.1 |
| RTL | Verilog-2001 (`.v`) |
| 기준 클럭 | 100 MHz, 10 ns |
| 입력/출력 | signed INT8 |
| Kernel | 고정 2×2 |
| Stride | runtime 1 또는 2 |
| 최대 입력 타일 | 기본 27×27 |

## 2. 타일 규격과 padding 책임

모듈은 **padding이 없는 valid 2×2 MaxPool**만 수행한다. 필요한 halo와 padding은
PS가 입력 타일에 명시적으로 포함한다.

출력 크기는 다음과 같다.

```text
OUT_W = floor((IN_W - 2) / STRIDE) + 1
OUT_H = floor((IN_H - 2) / STRIDE) + 1
```

대표적인 사용은 다음과 같다.

| 용도 | 입력 | Stride | 출력 |
| --- | ---: | ---: | ---: |
| 일반 downsample tile | 26×26 | 2 | 13×13 |
| 동일 크기 stride-1 tile | 27×27 | 1 | 26×26 |
| 13×13 stride-1 feature map | 14×14 | 1 | 13×13 |

경계 밖 padding 값은 signed INT8 최솟값 `-128`을 사용한다.

```text
실제 값이 모두 음수일 수 있으므로 padding에 0을 사용하면 안 된다.
padding = -128
```

예를 들어 13×13 feature map에 2×2, stride 1을 적용해 13×13 출력을 유지해야
한다면 PS가 golden model의 padding 방향에 맞춰 필요한 한 줄/한 열을 `-128`로
추가하여 14×14 입력 타일을 만든다. 모듈은 전달받은 14×14 배열에 valid pool만
적용한다. Padding 방향과 feature-map 전역 좌표 해석은 본 모듈의 책임이 아니다.

## 3. 입력/출력 데이터 순서

입력과 출력은 모두 channel 하나의 row-major 순서다.

```text
input index  = row * IN_W  + col
output index = row * OUT_W + col
```

예를 들어 4×4 입력은 다음 순서로 들어온다.

```text
x00, x01, x02, x03,
x10, x11, x12, x13,
x20, x21, x22, x23,
x30, x31, x32, x33
```

2×2 stride 2 출력은 다음 순서다.

```text
max(x00,x01,x10,x11),
max(x02,x03,x12,x13),
max(x20,x21,x30,x31),
max(x22,x23,x32,x33)
```

모든 비교는 반드시 **signed INT8 비교**여야 한다.

```text
max(-1, -3) = -1
```

Unsigned 비교로 `8'hff`를 255로 해석하면 안 된다.

## 4. RTL 모듈 인터페이스

파일명과 모듈명은 다음을 사용한다.

```text
파일: rtl/pipeline_conv/maxpool2d_int8_tile.v
모듈: maxpool2d_int8_tile
```

필수 module declaration은 다음 형태로 작성한다.

```verilog
module maxpool2d_int8_tile #(
    parameter DATA_WIDTH = 8,
    parameter MAX_IN_W   = 27,
    parameter MAX_IN_H   = 27,
    parameter DIM_WIDTH  = 6,
    parameter TAG_WIDTH  = 24
)(
    input  wire clk,
    input  wire rst_n,

    input  wire                       cfg_valid_i,
    output wire                       cfg_ready_o,
    input  wire [1:0]                 cfg_stride_i,
    input  wire [DIM_WIDTH-1:0]       cfg_in_width_i,
    input  wire [DIM_WIDTH-1:0]       cfg_in_height_i,
    input  wire [TAG_WIDTH-1:0]       cfg_tag_i,

    input  wire signed [DATA_WIDTH-1:0] s_data_i,
    input  wire                         s_valid_i,
    output wire                         s_ready_o,
    input  wire                         s_last_i,

    output wire signed [DATA_WIDTH-1:0] m_data_o,
    output wire                         m_valid_o,
    input  wire                         m_ready_i,
    output wire                         m_last_o,
    output wire        [TAG_WIDTH-1:0]  m_tag_o,

    output wire        busy_o,
    output wire        done_o,
    output wire [2:0]  error_o
);
```

### 4.1 Configuration handshake

새 타일 설정은 다음 조건에서 수락한다.

```text
cfg_fire = cfg_valid_i && cfg_ready_o
```

`cfg_ready_o`는 idle 상태에서만 1이다. 설정을 수락하면 아래 값을 내부 레지스터에
저장하고 input/output counter를 0으로 초기화한다.

- stride
- input width/height
- 계산된 output width/height
- tile tag

Busy 상태에서 들어온 config는 수락하지 않는다.

### 4.2 Port 의미

| 포트 | 의미 |
| --- | --- |
| `cfg_stride_i` | 1 또는 2만 허용 |
| `cfg_in_width_i` | 실제 packet의 한 row pixel 수 |
| `cfg_in_height_i` | 실제 packet의 row 수 |
| `cfg_tag_i` | 채널/타일 식별용 opaque tag |
| `s_data_i` | row-major signed INT8 input pixel |
| `s_last_i` | 입력 packet의 마지막 pixel |
| `m_data_o` | row-major signed INT8 pooled pixel |
| `m_last_o` | 마지막 output pixel |
| `m_tag_o` | 설정 시 수락한 tag를 모든 output에 전달 |
| `busy_o` | 설정 수락 후 마지막 출력 완료 전까지 1 |
| `done_o` | 마지막 출력 handshake cycle의 1-cycle pulse |
| `error_o` | 현재 타일의 protocol/config error |

### 4.3 Error bit 정의

| Bit | 이름 | 조건 |
| :---: | --- | --- |
| `0` | EARLY_TLAST | 예상 마지막 input 전 `s_last_i=1` |
| `1` | MISSING_TLAST | 예상 마지막 input에서 `s_last_i=0` |
| `2` | INVALID_CONFIG | stride/width/height가 유효 범위를 벗어남 |

`error_o`는 새 config 수락 시 0으로 초기화하고 현재 타일이 끝날 때까지 sticky로
유지한다. INVALID_CONFIG이면 input을 받지 않고 busy를 시작하지 않으며, error만
표시한 뒤 다음 config를 받을 수 있어야 한다.

## 5. 유효 Configuration

다음 조건을 모두 만족해야 한다.

```text
cfg_stride_i == 1 or cfg_stride_i == 2
2 <= cfg_in_width_i  <= MAX_IN_W
2 <= cfg_in_height_i <= MAX_IN_H
```

출력 크기는 내부에서 계산한다.

```text
out_width  = ((in_width  - 2) / stride) + 1
out_height = ((in_height - 2) / stride) + 1
```

나눗셈은 stride 1 또는 2뿐이므로 일반 divider를 만들지 않고 bypass 또는 1-bit
shift로 구현한다.

Stride 2에서 사용되지 않는 마지막 row/column이 존재할 수 있다. 위 floor 공식에
따라 완전히 포함되는 2×2 window만 출력하고 trailing pixel은 무시한다.

## 6. MaxPool 연산 규격

출력 `(oy, ox)`는 다음과 같다.

```text
base_y = oy * stride
base_x = ox * stride

output[oy][ox] = max(
    input[base_y    ][base_x    ],
    input[base_y    ][base_x + 1],
    input[base_y + 1][base_x    ],
    input[base_y + 1][base_x + 1]
)
```

같은 값이 여러 개면 어느 값을 선택했는지는 중요하지 않다. 출력 값만 정확히
일치하면 된다.

## 7. 권장 streaming 구현

전체 타일 RAM은 필요하지 않다. 다음 상태만으로 구현할 수 있다.

- 이전 row 저장용 `MAX_IN_W × INT8` line buffer 하나
- 현재 row의 이전 pixel
- 이전 row에서 읽은 이전 column pixel
- input row/column counter
- output holding register

현재 입력 pixel이 `(row, col)`일 때 `row>=1`, `col>=1`이면 2×2 후보는 다음이다.

```text
top_left     = 이전 row, col-1
top_right    = 이전 row, col
bottom_left  = 현재 row, col-1
bottom_right = 현재 input pixel
```

Output을 만드는 위치 조건은 다음과 같다.

```text
row = 1 + oy * stride
col = 1 + ox * stride
```

따라서:

```text
stride 1: row>=1, col>=1인 모든 위치에서 output
stride 2: row와 col이 1,3,5,...인 위치에서 output
```

Line buffer를 현재 row pixel로 덮어쓸 때 top-left 값이 사라지지 않도록 이전
column의 old line-buffer 값을 별도 레지스터에 보존한다.

MAX_IN_W 기본값이 27이므로 register/distributed memory 구현도 허용한다. Vivado
합성 결과가 100 MHz를 만족하고 signed comparison이 정확하면 내부 구조는 자유다.

## 8. Ready/valid와 backpressure

입력과 출력 handshake는 다음과 같다.

```text
input_fire  = s_valid_i && s_ready_o
output_fire = m_valid_o && m_ready_i
```

필수 동작:

1. Input counter와 line buffer는 `input_fire`에서만 갱신한다.
2. Output은 해당 input pixel이 실제 수락된 뒤에만 생성한다.
3. `m_valid_o=1 && m_ready_i=0`이면 `m_data_o`, `m_last_o`, `m_tag_o`,
   `m_valid_o`를 안정적으로 유지한다.
4. Pending output을 덮어쓸 수 있는 input은 받지 않는다.
5. 가장 단순한 구현은 `!m_valid_o || m_ready_i`일 때만 input을 받는 1-entry
   output holding register다.
6. Output이 발생하지 않는 input cycle까지 불필요하게 막지 않는 최적화는
   선택사항이다.
7. Reset 시 config, counters, line buffer valid, pending output을 폐기한다.
8. 출력 순서를 바꾸거나 누락/중복하지 않는다.

Stall이 없을 때 입력 pixel 한 개/cycle을 받을 수 있어야 한다. Stride 1에서는
steady state에서 output도 최대 한 개/cycle 발생한다.

`done_o`는 최종 `m_last_o && m_valid_o && m_ready_i` handshake cycle에만 1이다.
Downstream이 정지해 있으면 done도 함께 지연되어야 한다.

## 9. TLAST 규격

예상 input pixel 수:

```text
expected_input_count = in_width * in_height
```

`s_last_i`는 zero-based input index가 `expected_input_count-1`일 때만 1이어야 한다.

예상 output pixel 수:

```text
expected_output_count = out_width * out_height
```

`m_last_o`는 zero-based output index가 `expected_output_count-1`인 결과에만 1이다.

Input TLAST가 잘못되어도 row/column 진행은 설정된 input count를 기준으로 하며,
잘못된 TLAST 자체로 packet을 조기 종료하지 않는다. Error를 기록하고 설정된 수의
입력을 계속 처리한다.

## 10. 기준 Python 함수

RTL 결과는 아래 함수와 bit-exact하게 일치해야 한다.

```python
import numpy as np


def maxpool2x2_valid_int8(tile: np.ndarray, stride: int) -> np.ndarray:
    tile = np.asarray(tile, dtype=np.int8)
    if tile.ndim != 2:
        raise ValueError("tile must be a 2-D single-channel array")
    if stride not in (1, 2):
        raise ValueError("stride must be 1 or 2")

    in_h, in_w = tile.shape
    if in_h < 2 or in_w < 2:
        raise ValueError("input dimensions must be at least 2")

    out_h = ((in_h - 2) // stride) + 1
    out_w = ((in_w - 2) // stride) + 1
    out = np.empty((out_h, out_w), dtype=np.int8)

    for oy in range(out_h):
        for ox in range(out_w):
            iy = oy * stride
            ix = ox * stride
            out[oy, ox] = np.max(tile[iy:iy + 2, ix:ix + 2])

    return out
```

## 11. 필수 directed test

### 11.1 4×4, stride 2

입력:

```text
 -1  -2   3   4
  5   6  -7   8
  9 -10  11  12
-13  14  15 -16
```

예상 출력:

```text
 6   8
14  15
```

### 11.2 3×3, stride 1, 모든 값이 음수

입력:

```text
-5 -2 -9
-4 -8 -1
-7 -3 -6
```

예상 출력:

```text
-2 -1
-3 -1
```

### 11.3 추가 필수 항목

- 모든 값이 -128인 입력
- 동일한 최댓값이 여러 개 있는 입력
- 26×26 stride 2 → 13×13
- 27×27 stride 1 → 26×26
- 14×14 stride 1 → 13×13
- right/bottom 또는 golden model이 요구한 halo가 -128인 경계 입력
- stride 2에서 trailing row/column이 무시되는 홀수 입력
- early TLAST, missing TLAST, invalid config

## 12. 테스트벤치 요구사항

```text
파일: rtl/tb/tb_maxpool2d_int8_tile.v
top:  tb_maxpool2d_int8_tile
```

테스트벤치는 다음을 자동 판정한다.

1. Section 11 directed test 전체
2. stride 1과 stride 2
3. 최소 1,000개의 deterministic random tile
4. 모든 결과를 Python/동일 산술 golden과 비교
5. signed 음수 비교
6. 불규칙한 `s_valid_i`
7. 장시간 `m_ready_i=0` backpressure
8. stall 동안 output payload 안정성
9. 입력 및 출력 TLAST 위치
10. output count와 row-major 순서
11. tag 전달
12. error bit sticky/clear 동작
13. processing 도중 reset 후 stale output이 없는지 확인
14. 연속 config/tile 실행

Random seed는 고정하고 구현 메모에 기록한다.

성공 시 마지막 줄은 다음 형식을 사용한다.

```text
PASS: tb_maxpool2d_int8_tile directed=<N> random_tiles=1000 stalls=<N>
```

## 13. 합성 및 타이밍 요구사항

```text
part: xc7z020clg400-1
clock: 10.000 ns
top: maxpool2d_int8_tile
Vivado: 2024.1
```

Acceptance 조건:

- simulation PASS
- 합성 error/critical warning 없음
- latch와 combinational loop 없음
- setup `WNS >= 0 ns`
- hold violation 없음
- signed compare가 comparator로 정상 합성됨
- line buffer가 최대 폭 27에 비례하며 full feature-map 크기에 비례하지 않음
- backpressure 경로가 10 ns timing을 만족함

Utilization report에 LUT, FF, BRAM/LUTRAM 및 no-stall 처리율을 기록한다.

## 14. 프로젝트 통합 규칙

모듈은 standalone이어야 하며 다음을 직접 instantiate하지 않는다.

- convolution 또는 activation
- requantization
- AXI packer/FIFO/DMA
- 전체 feature-map memory
- channel/tile scheduler

상위 모듈이 채널별 타일과 padding/halo를 준비한다.

```text
requant valid/ready INT8 stream
→ maxpool2d_int8_tile
→ INT8 output adapter/FIFO
```

Pool이 없는 convolution layer에서는 상위 mux가 MaxPool을 bypass한다. MaxPool
사용 여부를 본 모듈 내부에 추가하지 않는다.

## 15. 요청 범위에 포함하지 않는 기능

- Padding 생성
- Average pooling
- 3×3 또는 가변 kernel pooling
- Cross-channel pooling
- Activation/requantization
- INT8 4-lane packing
- 전체 feature-map 주소 생성
- DMA와 AXI-Lite 제어
- route/concat/upsample

## 16. 제출 파일

```text
rtl/pipeline_conv/maxpool2d_int8_tile.v
rtl/tb/tb_maxpool2d_int8_tile.v
rtl/filelists/maxpool_tb.f
Python golden 또는 fixture 생성 파일
구현 메모/README
Vivado simulation PASS 로그
Vivado OOC utilization report
Vivado OOC timing summary
```

구현 메모에는 다음을 기록한다.

- config-to-first-input 허용 latency
- input/output no-stall 처리율
- line buffer 구현 방식
- LUT/FF/BRAM 사용량
- WNS/TNS
- random seed
- 알려진 제한사항

## 17. 완료 체크리스트

- [ ] 2×2 stride 1/2가 Python reference와 bit-exact하다.
- [ ] 모든 비교가 signed INT8이다.
- [ ] Padding을 내부에서 임의로 생성하지 않는다.
- [ ] -128 halo가 실제 음수보다 우선 선택되지 않는다.
- [ ] Input/output count와 TLAST가 정확하다.
- [ ] tag가 모든 output에 올바르게 전달된다.
- [ ] output stall 동안 payload가 유지된다.
- [ ] reset 후 stale output이 없다.
- [ ] invalid config와 TLAST error가 표시된다.
- [ ] deterministic random tile 1,000개 이상을 통과한다.
- [ ] XC7Z020-1, 100 MHz에서 `WNS >= 0`이다.

위 항목이 모두 충족되어야 requantized INT8 tile stream 뒤에 통합한다.
