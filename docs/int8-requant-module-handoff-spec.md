# INT32 → INT8 Requantization RTL 모듈 제작 요청서

## 1. 문서 목적

이 문서는 PYNQ-Z2용 YOLOv3-Tiny CNN 가속기에 연결할 **INT32 → INT8
requantization 하위 모듈**의 제작 규격이다. 제작자는 이 문서만으로 RTL,
테스트벤치, 합성 검증을 완료할 수 있어야 한다.

이 모듈은 convolution의 최종 INT32 누산값을 채널별 정수 scale로 변환하고,
반올림과 zero-point 적용 후 signed INT8 범위로 포화한다. 입력과 출력은
ready/valid handshake를 사용하며, downstream 정지 시 데이터와 태그를 손실하지
않아야 한다.

대상 환경은 다음과 같다.

| 항목 | 값 |
| --- | --- |
| FPGA | Xilinx XC7Z020-1 (`xc7z020clg400-1`) |
| 보드 | TUL PYNQ-Z2 |
| 도구 | Vivado 2024.1 |
| RTL | Verilog-2001 (`.v`) |
| 기준 클럭 | 100 MHz, 10 ns |
| 입력 | signed INT32 accumulator |
| 출력 | signed INT8 activation |

## 2. 시스템 내 연결 위치

예정된 데이터 경로는 다음과 같다.

```text
3x3/1x1 convolution
→ IC block partial-sum RAM
→ 마지막 IC block의 최종 INT32 값
→ optional INT32 activation
→ [이 문서의 requant 모듈]
→ INT8 packer 또는 32-bit AXI word의 low byte
→ AXI-Stream output FIFO
→ AXI DMA S2MM
→ PS DDR
```

이 모듈은 convolution, bias 저장, BatchNorm, Leaky ReLU, AXI packing을 직접
수행하지 않는다. Bias와 BatchNorm folding이 반영된 최종 accumulator가 입력으로
들어온다고 가정한다.

초기 통합에서는 INT8 출력 하나를 AXI 32-bit word 하나에 넣는다.

```text
TDATA[7:0]  = requant 결과의 8-bit two's-complement bit pattern
TDATA[31:8] = 0
```

INT8 네 개를 한 word에 넣는 packer는 별도 모듈이며 본 요청 범위가 아니다.

## 3. 필수 산술 규격

모듈은 입력 transaction마다 다음 값을 받는다.

- `acc`: signed INT32 최종 누산값
- `multiplier`: signed INT32 정수 multiplier
- `shift`: unsigned 6-bit right shift, 유효 범위 0~63
- `zero_point`: signed INT32 출력 zero-point, 현재 대칭 양자화에서는 0

실수 scale은 offline tool에서 다음 형태로 근사한다.

```text
real_scale ≈ multiplier / 2^shift
```

모듈의 연산은 반드시 다음 순서를 따른다.

```text
product = signed_int64(acc) * signed_int64(multiplier)

if shift == 0:
    scaled = product
else:
    magnitude = abs(product)
    rounded_magnitude = (magnitude + 2^(shift-1)) >> shift
    scaled = -rounded_magnitude if product < 0 else rounded_magnitude

with_zero_point = scaled + zero_point
output = clamp(with_zero_point, -128, 127)
```

반올림 방식은 **round to nearest, exact half는 0에서 멀어지는 방향**이다.

```text
 3 / 2  →  2
-3 / 2  → -2
 5 / 2  →  3
-5 / 2  → -3
```

Verilog의 signed arithmetic right shift에 rounding bias를 직접 더하면 음수에서
규격이 달라질 수 있으므로, 위 규격처럼 절댓값에서 반올림한 뒤 부호를 복원해야
한다.

### 3.1 내부 비트 폭

- 32×32 signed 곱은 최소 signed 64-bit로 보존한다.
- `abs(product) + rounding_bias`는 overflow 방지를 위해 최소 65-bit unsigned
  magnitude로 계산한다.
- `zero_point`를 더하기 전에 중간값을 8-bit로 자르지 않는다.
- 포화 비교가 끝난 뒤에만 INT8로 변환한다.

### 3.2 포화와 clip 표시

```text
with_zero_point >  127 → output =  127, clipped = 1
with_zero_point < -128 → output = -128, clipped = 1
그 외                  → output = 원래 값, clipped = 0
```

`clipped`는 디버그 및 saturation 통계용이다. 출력 데이터의 유효 여부는
`valid_o`로 판단하며 `clipped_o`만 단독으로 사용하지 않는다.

## 4. RTL 모듈 인터페이스

파일명과 모듈명은 다음을 사용한다.

```text
파일: rtl/active/datapath/requant_int32_to_int8.v
모듈: requant_int32_to_int8
```

필수 module declaration은 다음 형태로 작성한다.

```verilog
module requant_int32_to_int8 #(
    parameter ACC_WIDTH        = 32,
    parameter MULT_WIDTH       = 32,
    parameter SHIFT_WIDTH      = 6,
    parameter ZERO_POINT_WIDTH = 32,
    parameter TAG_WIDTH        = 24
)(
    input  wire clk,
    input  wire rst_n,

    input  wire signed [ACC_WIDTH-1:0]        acc_i,
    input  wire signed [MULT_WIDTH-1:0]       multiplier_i,
    input  wire        [SHIFT_WIDTH-1:0]      shift_i,
    input  wire signed [ZERO_POINT_WIDTH-1:0] zero_point_i,
    input  wire        [TAG_WIDTH-1:0]        tag_i,
    input  wire                               last_i,
    input  wire                               valid_i,
    output wire                               ready_o,

    output wire signed [7:0]                  data_o,
    output wire                               clipped_o,
    output wire        [TAG_WIDTH-1:0]        tag_o,
    output wire                               last_o,
    output wire                               valid_o,
    input  wire                               ready_i
);
```

### 4.1 포트 의미

| 포트 | 방향 | 의미 |
| --- | --- | --- |
| `clk` | input | 단일 동기 클럭 |
| `rst_n` | input | active-low asynchronous reset |
| `acc_i` | input | bias 및 IC 누적이 완료된 signed INT32 값 |
| `multiplier_i` | input | 현재 출력 채널의 signed 정수 multiplier |
| `shift_i` | input | unsigned right shift 0~63 |
| `zero_point_i` | input | 출력 zero-point, 초기 대칭 양자화에서는 0 |
| `tag_i` | input | 주소/채널/타일 식별용 opaque tag |
| `last_i` | input | 현재 output packet의 마지막 값 표시 |
| `valid_i` | input | 모든 입력 payload가 유효함 |
| `ready_o` | output | 모듈이 현재 입력 transaction을 받을 수 있음 |
| `data_o` | output | signed INT8 requant 결과 |
| `clipped_o` | output | 해당 결과가 -128 또는 127로 포화됨 |
| `tag_o` | output | 입력 transaction의 `tag_i`를 그대로 전달 |
| `last_o` | output | 입력 transaction의 `last_i`를 그대로 전달 |
| `valid_o` | output | 모든 출력 payload가 유효함 |
| `ready_i` | input | downstream이 현재 출력을 받을 수 있음 |

`tag_i`의 bit layout은 requant 모듈이 해석하지 않는다. 입력 tag를 해당 결과와
동일한 순서로 출력하기만 한다.

## 5. Ready/valid 동작 규격

입력 transaction 수락 조건은 다음과 같다.

```text
input_fire = valid_i && ready_o
```

출력 transaction 완료 조건은 다음과 같다.

```text
output_fire = valid_o && ready_i
```

필수 동작은 다음과 같다.

1. `valid_i && ready_o`인 transaction만 계산 파이프라인에 들어간다.
2. 수락된 transaction은 정확히 한 번 출력된다.
3. transaction 순서를 바꾸지 않는다.
4. 입력이 없는 cycle에는 임의의 새 결과를 만들지 않는다.
5. `valid_o=1 && ready_i=0`인 동안 아래 출력은 모두 안정적으로 유지한다.
   - `data_o`
   - `clipped_o`
   - `tag_o`
   - `last_o`
   - `valid_o`
6. downstream stall은 내부 pipeline을 통해 안전하게 전파되거나 충분한 elastic
   register/FIFO로 흡수되어야 한다.
7. reset이 assertion되면 수락되었지만 아직 출력되지 않은 transaction은 폐기하고
   `valid_o`를 0으로 만든다.

### 5.1 처리율과 latency

- 목표 initiation interval은 1이다. Stall이 없으면 매 cycle 입력 하나를 받을 수
  있어야 한다.
- stall이 없을 때의 내부 latency는 제작자가 정할 수 있으나 반드시 고정되어야
  하고 README에 cycle 수를 기록해야 한다. Backpressure가 걸린 동안 실제 출력
  시점은 그만큼 늦어질 수 있다.
- 실제 통합은 ready/valid로 이루어지므로 상위 RTL이 고정 latency를 가정하지
  않게 한다.
- 100 MHz에서 timing closure를 만족하도록 multiplier, rounding, saturation을
  필요한 만큼 pipeline한다.

## 6. 권장 구현 단계

구현 방식은 자유지만 다음 단계 분리를 권장한다.

```text
Stage 0: acc/multiplier/shift/zero_point/tag/last 수락
Stage 1: signed 32×32 multiply → signed 64-bit product
Stage 2: sign/magnitude 변환 + rounding bias + right shift
Stage 3: zero-point add + INT8 saturation + clipped 생성
Stage 4: output holding register
```

각 stage는 valid와 payload/tag를 함께 이동해야 한다. Backpressure 대응은 각 stage를
elastic pipeline으로 만들거나, 계산 pipeline 뒤에 입력 수용량을 보장하는 FIFO를
두는 방법을 사용할 수 있다.

단순 shift-register valid pipeline인데 output stall 시 앞단이 계속 진행하여 결과를
덮어쓰는 구현은 허용하지 않는다.

## 7. 산술 기준 Python 코드

RTL golden model은 아래 함수와 bit-exact하게 일치해야 한다.

```python
def requant_int32_to_int8(acc: int, multiplier: int, shift: int,
                          zero_point: int = 0) -> tuple[int, bool]:
    if not 0 <= shift <= 63:
        raise ValueError("shift must be in [0, 63]")

    product = int(acc) * int(multiplier)

    if shift == 0:
        scaled = product
    else:
        magnitude = abs(product)
        rounded_magnitude = (
            magnitude + (1 << (shift - 1))
        ) >> shift
        scaled = -rounded_magnitude if product < 0 else rounded_magnitude

    shifted = scaled + int(zero_point)
    clipped = shifted < -128 or shifted > 127
    output = max(-128, min(127, shifted))
    return output, clipped
```

## 8. 필수 directed test vector

최소한 아래 벡터를 모두 검증해야 한다.

| `acc` | `multiplier` | `shift` | `zero_point` | 예상 출력 | clip |
| ---: | ---: | ---: | ---: | ---: | :---: |
| 0 | 1 | 0 | 0 | 0 | 0 |
| 100 | 1 | 1 | 0 | 50 | 0 |
| -100 | 1 | 1 | 0 | -50 | 0 |
| 3 | 1 | 1 | 0 | 2 | 0 |
| -3 | 1 | 1 | 0 | -2 | 0 |
| 5 | 3 | 2 | 0 | 4 | 0 |
| -5 | 3 | 2 | 0 | -4 | 0 |
| 117 | 1 | 0 | 10 | 127 | 0 |
| 118 | 1 | 0 | 10 | 127 | 1 |
| -118 | 1 | 0 | -10 | -128 | 0 |
| -119 | 1 | 0 | -10 | -128 | 1 |
| 1000 | 1 | 0 | 0 | 127 | 1 |
| -1000 | 1 | 0 | 0 | -128 | 1 |
| 123456789 | 0 | 17 | 0 | 0 | 0 |
| -2147483648 | 2147483647 | 63 | 0 | 0 | 0 |
| -2147483648 | -2147483648 | 63 | 0 | 1 | 0 |

마지막 벡터를 포함하여 Python reference와 실제 값을 다시 산출해 testbench 상수의
오타가 없는지 확인한다.

## 9. 필수 테스트벤치 동작

파일명과 top module은 다음을 사용한다.

```text
파일: rtl/tb/current/tb_requant_int32_to_int8.v
top:  tb_requant_int32_to_int8
```

테스트벤치는 아래 항목을 자동 판정해야 한다.

1. Section 8의 모든 directed vector
2. 최소 10,000개의 deterministic random vector
3. `valid_i`가 불규칙하게 비는 경우
4. `ready_i`가 장시간 0인 경우
5. input과 output handshake가 동시에 일어나는 경우
6. 연속 입력에서 initiation interval 1 확인
7. `tag`와 `last`가 각 데이터와 정확히 정렬되는지 확인
8. stall 동안 모든 output payload가 안정적인지 확인
9. pipeline 중간 reset 후 stale output이 나오지 않는지 확인
10. 출력 개수와 입력 수락 개수가 정확히 같은지 확인

Random test는 seed를 고정하여 재현 가능해야 한다. 예상값은 Section 7과 동일한
산술을 testbench 함수로 구현하거나, Python이 생성한 fixture를 사용한다.

성공 시 마지막에 다음 형식의 한 줄을 출력한다.

```text
PASS: tb_requant_int32_to_int8 directed=<N> random=10000 stalls=<N>
```

오류가 발생하면 첫 mismatch에서 최소한 다음 정보를 출력한다.

```text
transaction index
acc, multiplier, shift, zero_point
expected data/clip/tag/last
actual data/clip/tag/last
```

## 10. 합성 및 타이밍 요구사항

Vivado 2024.1에서 다음 조건으로 out-of-context synthesis를 수행한다.

```text
part: xc7z020clg400-1
clock: 10.000 ns
top: requant_int32_to_int8
```

필수 acceptance 조건:

- 합성 error와 critical warning 없음
- latch 없음
- combinational loop 없음
- setup `WNS >= 0 ns`
- hold violation 없음
- ready/valid 경로가 10 ns timing을 만족함

DSP, LUT, FF 사용량에는 강제 상한을 두지 않지만, 32×32 multiplier가 몇 개의
DSP48E1으로 합성되는지 utilization report에 기록한다. 동일 동작을 유지하면서
불필요하게 multiplier를 복제하지 않는다.

## 11. 프로젝트 통합 규칙

모듈은 standalone이어야 하며 아래 모듈을 직접 instantiate하지 않는다.

- convolution datapath
- AXI DMA 또는 AXI-Stream wrapper
- weight/bias/scale memory
- activation
- output FIFO

상위 모듈이 현재 output channel에 맞는 `multiplier_i`, `shift_i`,
`zero_point_i`를 제공한다. 해당 parameter는 `valid_i && ready_o`인 cycle에
`acc_i`와 함께 샘플링해야 하며 transaction 처리 도중 외부 값이 변경되어도 결과에
영향을 주면 안 된다.

통합 시 기존 INT32 result ready/valid 경로에 다음처럼 삽입할 예정이다.

```text
tile accumulator result_valid/result_ready
→ requant valid_i/ready_o
→ requant valid_o/ready_i
→ INT8 output adapter/FIFO
```

`tag`에는 output address와 필요한 channel/tile 식별자가 들어간다. `last`는 최종
AXI packet의 TLAST 생성에 사용된다.

## 12. 요청 범위에 포함하지 않는 기능

다음은 별도 모듈 또는 상위 제어의 책임이며 이번 작업에 넣지 않는다.

- BatchNorm folding
- multiplier/shift를 계산하는 offline quantization tool
- bias memory
- Leaky ReLU, ReLU, sigmoid
- 1x1/3x3 convolution
- IC/OC channel loop
- INT8 4-lane packer
- AXI-Lite register interface
- DMA 제어
- MaxPool, route, upsample, YOLO decode, NMS

요청 범위를 넘어 activation mode나 parameter RAM을 임의로 추가하지 않는다.

## 13. 제출 파일

완료 시 아래 파일을 전달한다.

```text
rtl/active/datapath/requant_int32_to_int8.v
rtl/tb/current/tb_requant_int32_to_int8.v
rtl/filelists/requant_tb.f
tests 또는 scripts 아래 Python golden/fixture 생성 파일
README 또는 간단한 구현 메모
Vivado simulation PASS 로그
Vivado OOC utilization report
Vivado OOC timing summary
```

구현 메모에는 다음을 기록한다.

- no-stall latency cycle 수
- initiation interval
- stall 처리 방법
- DSP/LUT/FF 사용량
- WNS/TNS
- 사용한 random seed
- 알려진 제한사항

## 14. 최종 완료 체크리스트

- [ ] Section 3의 산술과 Python reference가 bit-exact하게 일치한다.
- [ ] 음수 exact-half 반올림이 0에서 멀어지는 방향이다.
- [ ] INT8 포화 경계 -128과 127이 정확하다.
- [ ] `shift=0`과 `shift=63`이 정상 동작한다.
- [ ] tag와 last가 data와 함께 전달된다.
- [ ] output stall 동안 모든 output payload가 유지된다.
- [ ] reset 후 stale transaction이 출력되지 않는다.
- [ ] 매 cycle 입력을 받을 수 있다.
- [ ] deterministic random 10,000개 이상을 통과한다.
- [ ] XC7Z020-1, 100 MHz 합성에서 `WNS >= 0`이다.
- [ ] 제출 파일과 보고서가 모두 포함되어 있다.

위 체크리스트가 모두 충족되어야 상위 convolution/tile pipeline 통합을 진행한다.
