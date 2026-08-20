# INT32 Activation RTL 모듈 제작 요청서

## 1. 문서 목적

이 문서는 PYNQ-Z2용 YOLOv3-Tiny CNN 가속기에 연결할 **INT32 activation
하위 모듈**의 제작 규격이다. 제작자는 이 문서만으로 RTL, 테스트벤치, 합성
검증을 완료할 수 있어야 한다.

모듈은 convolution과 bias 누적이 끝난 signed INT32 값을 받아 다음 activation
중 하나를 적용한다.

- Linear/bypass
- Leaky ReLU
- ReLU

Activation은 INT8 saturation 전에 수행해야 하므로 requantization 모듈 앞에
배치한다.

```text
INT32 tile accumulator
→ [이 문서의 activation 모듈]
→ INT32→INT8 requantization
→ optional INT8 MaxPool
→ AXI output
```

대상 환경은 다음과 같다.

| 항목 | 값 |
| --- | --- |
| FPGA | Xilinx XC7Z020-1 (`xc7z020clg400-1`) |
| 보드 | TUL PYNQ-Z2 |
| 도구 | Vivado 2024.1 |
| RTL | Verilog-2001 (`.v`) |
| 기준 클럭 | 100 MHz, 10 ns |
| 입력/출력 | signed INT32 |

## 2. 기존 모듈과 교체 이유

현재 프로젝트의 `rtl/active/datapath/activation.v`는 음수 값을 단순 arithmetic
right shift한다.

```verilog
assign data_o = (data_i >= 0) ? data_i : (data_i >>> LEAKY_SHIFT);
```

기본 `LEAKY_SHIFT=3`은 음수 slope를 `1/8=0.125`로 근사한다. YOLOv3-Tiny의
Leaky ReLU slope와 bit-exact하게 일치하지 않을 수 있고 ready/valid 및
backpressure도 지원하지 않는다.

새 모듈은 slope를 `multiplier / 2^shift`로 표현하고, 양수와 음수의 반올림을
명시적으로 정의하며, 태그와 packet-last를 함께 전달한다.

## 3. Activation mode

`mode_i` 값은 다음으로 고정한다.

| `mode_i` | 이름 | 연산 |
| :---: | --- | --- |
| `2'b00` | LINEAR | `y = x` |
| `2'b01` | LEAKY_RELU | `x>=0 ? x : round(x × negative_slope)` |
| `2'b10` | RELU | `x>=0 ? x : 0` |
| `2'b11` | RESERVED | LINEAR로 동작하고 `mode_error_o=1` |

YOLO detection head의 마지막 convolution은 LINEAR를 사용한다. 일반적인
YOLOv3-Tiny convolution은 offline model metadata가 지정한 LEAKY_RELU를
사용한다.

## 4. Leaky ReLU 산술 규격

음수 slope는 transaction마다 다음 정수 비율로 제공한다.

```text
negative_slope ≈ negative_multiplier / 2^negative_shift
```

- `negative_multiplier`: unsigned 16-bit
- `negative_shift`: unsigned 6-bit, 유효 범위 0~63

Leaky ReLU 연산은 반드시 다음과 같다.

```text
if x >= 0:
    y_wide = x
else:
    magnitude = abs(x)
    product = magnitude * negative_multiplier

    if negative_shift == 0:
        rounded_magnitude = product
    else:
        rounded_magnitude =
            (product + 2^(negative_shift-1)) >> negative_shift

    y_wide = -rounded_magnitude

y = saturate_to_int32(y_wide)
```

반올림은 **round to nearest, exact half는 0에서 멀어지는 방향**이다.

```text
-12 × 1/8 = -1.5 → -2
 -4 × 1/8 = -0.5 → -1
 -3 × 1/8 = -0.375 → 0
```

양수 입력은 multiplier와 shift 값에 관계없이 원래 값을 그대로 출력한다.

### 4.1 권장 0.1 slope 표현

0.1을 예로 들면 offline tool이 다음과 같이 표현할 수 있다.

```text
negative_multiplier = 3277
negative_shift      = 15
3277 / 32768 ≈ 0.1000061
```

최종 multiplier/shift 값은 Python quantization policy가 결정한다. RTL 내부에
0.1 또는 특정 shift를 hard-code하지 않는다.

### 4.2 내부 비트 폭과 saturation

- `abs(INT32_MIN)`을 표현하기 위해 magnitude는 최소 33-bit unsigned로 둔다.
- 33×16 product는 최소 49-bit unsigned로 보존한다.
- `negative_shift=63`의 rounding bias까지 표현할 수 있도록 rounding 임시값은
  최소 64-bit unsigned로 둔다.
- 결과가 signed INT32 범위를 벗어나면 포화한다.

```text
y_wide >  2147483647 → data_o =  2147483647, clipped_o = 1
y_wide < -2147483648 → data_o = -2147483648, clipped_o = 1
그 외                 → data_o = y_wide,       clipped_o = 0
```

정상적인 `0 <= negative_slope <= 1`에서는 overflow가 발생하지 않지만 잘못된
parameter가 들어와도 wrap-around하지 않아야 한다.

## 5. RTL 모듈 인터페이스

파일명과 모듈명은 다음을 사용한다.

```text
파일: rtl/active/datapath/activation_int32_stream.v
모듈: activation_int32_stream
```

필수 module declaration은 다음 형태로 작성한다.

```verilog
module activation_int32_stream #(
    parameter DATA_WIDTH       = 32,
    parameter SLOPE_MULT_WIDTH = 16,
    parameter SHIFT_WIDTH      = 6,
    parameter TAG_WIDTH        = 24
)(
    input  wire clk,
    input  wire rst_n,

    input  wire signed [DATA_WIDTH-1:0]       data_i,
    input  wire        [1:0]                  mode_i,
    input  wire        [SLOPE_MULT_WIDTH-1:0] negative_multiplier_i,
    input  wire        [SHIFT_WIDTH-1:0]      negative_shift_i,
    input  wire        [TAG_WIDTH-1:0]        tag_i,
    input  wire                               last_i,
    input  wire                               valid_i,
    output wire                               ready_o,

    output wire signed [DATA_WIDTH-1:0]       data_o,
    output wire                               clipped_o,
    output wire                               mode_error_o,
    output wire        [TAG_WIDTH-1:0]        tag_o,
    output wire                               last_o,
    output wire                               valid_o,
    input  wire                               ready_i
);
```

### 5.1 포트 의미

| 포트 | 방향 | 의미 |
| --- | --- | --- |
| `clk` | input | 단일 동기 클럭 |
| `rst_n` | input | active-low asynchronous reset |
| `data_i` | input | activation 전 signed INT32 값 |
| `mode_i` | input | LINEAR/LEAKY_RELU/RELU 선택 |
| `negative_multiplier_i` | input | Leaky 음수 slope의 정수 multiplier |
| `negative_shift_i` | input | Leaky 음수 slope의 right shift |
| `tag_i` | input | 주소/채널/타일 식별용 opaque tag |
| `last_i` | input | packet의 마지막 값 표시 |
| `valid_i` | input | 모든 입력 payload가 유효함 |
| `ready_o` | output | 현재 입력 transaction 수락 가능 |
| `data_o` | output | activation 결과 signed INT32 |
| `clipped_o` | output | INT32 saturation 발생 표시 |
| `mode_error_o` | output | reserved mode가 입력되었음 |
| `tag_o` | output | 입력 tag 전달 |
| `last_o` | output | 입력 last 전달 |
| `valid_o` | output | 모든 출력 payload가 유효함 |
| `ready_i` | input | downstream requant 모듈이 결과 수락 가능 |

`mode_i`, multiplier, shift는 `valid_i && ready_o`인 cycle에 data/tag와 함께
샘플링해야 한다. Transaction 처리 중 외부 값이 바뀌어도 이미 수락된 결과에
영향을 주면 안 된다.

## 6. Ready/valid 규격

```text
input_fire  = valid_i && ready_o
output_fire = valid_o && ready_i
```

필수 동작:

1. 수락된 transaction을 정확히 한 번 출력한다.
2. 순서를 바꾸거나 데이터/tag/last를 분리하지 않는다.
3. `valid_o=1 && ready_i=0`이면 아래 값을 모두 안정적으로 유지한다.
   - `data_o`
   - `clipped_o`
   - `mode_error_o`
   - `tag_o`
   - `last_o`
   - `valid_o`
4. Reset 시 pipeline의 미출력 transaction을 폐기하고 `valid_o=0`으로 만든다.
5. Stall이 없으면 매 cycle 새 입력을 받을 수 있어야 한다.
6. No-stall latency는 고정하고 구현 메모에 기록한다. Backpressure 중 실제 출력
   시점은 늦어질 수 있다.

단순 조합 출력으로 구현해 ready/valid 조합 경로가 상위 accumulator부터 requant
모듈까지 길게 이어지지 않도록 한다. 100 MHz를 위해 필요한 pipeline 또는 output
holding register를 둔다.

## 7. 기준 Python 함수

RTL은 아래 함수와 bit-exact하게 일치해야 한다.

```python
MODE_LINEAR = 0
MODE_LEAKY = 1
MODE_RELU = 2

INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1


def activation_int32(x: int, mode: int,
                     negative_multiplier: int,
                     negative_shift: int) -> tuple[int, bool, bool]:
    if not 0 <= negative_shift <= 63:
        raise ValueError("negative_shift must be in [0, 63]")

    mode_error = mode not in (MODE_LINEAR, MODE_LEAKY, MODE_RELU)

    if mode == MODE_RELU:
        wide = max(0, int(x))
    elif mode == MODE_LEAKY and x < 0:
        product = abs(int(x)) * int(negative_multiplier)
        if negative_shift == 0:
            magnitude = product
        else:
            magnitude = (
                product + (1 << (negative_shift - 1))
            ) >> negative_shift
        wide = -magnitude
    else:
        # LINEAR, positive LEAKY input, and reserved mode
        wide = int(x)

    clipped = wide < INT32_MIN or wide > INT32_MAX
    output = max(INT32_MIN, min(INT32_MAX, wide))
    return output, clipped, mode_error
```

## 8. 필수 directed test vector

| `data_i` | mode | multiplier | shift | 예상 출력 | clip | mode error |
| ---: | --- | ---: | ---: | ---: | :---: | :---: |
| 0 | LINEAR | 0 | 0 | 0 | 0 | 0 |
| 2147483647 | LINEAR | 0 | 0 | 2147483647 | 0 | 0 |
| -2147483648 | LINEAR | 0 | 0 | -2147483648 | 0 | 0 |
| -5 | RELU | 0 | 0 | 0 | 0 | 0 |
| 7 | RELU | 0 | 0 | 7 | 0 | 0 |
| 7 | LEAKY | 1 | 3 | 7 | 0 | 0 |
| -8 | LEAKY | 1 | 3 | -1 | 0 | 0 |
| -12 | LEAKY | 1 | 3 | -2 | 0 | 0 |
| -4 | LEAKY | 1 | 3 | -1 | 0 | 0 |
| -3 | LEAKY | 1 | 3 | 0 | 0 | 0 |
| -100 | LEAKY | 3277 | 15 | -10 | 0 | 0 |
| -2147483648 | LEAKY | 1 | 0 | -2147483648 | 0 | 0 |
| -2147483648 | LEAKY | 2 | 0 | -2147483648 | 1 | 0 |
| 42 | RESERVED | 1 | 3 | 42 | 0 | 1 |

## 9. 테스트벤치 요구사항

```text
파일: rtl/tb/current/tb_activation_int32_stream.v
top:  tb_activation_int32_stream
```

테스트벤치는 다음을 자동 판정한다.

1. Section 8 directed vector 전체
2. 모든 activation mode
3. 최소 10,000개의 deterministic random vector
4. INT32_MIN/INT32_MAX와 saturation 경계
5. 양수 LEAKY 입력이 multiplier와 무관하게 bypass되는지 확인
6. exact-half 음수 rounding 확인
7. 불규칙한 `valid_i`
8. 장시간 `ready_i=0` backpressure
9. stall 동안 output payload 안정성
10. tag/last 정렬
11. pipeline 중간 reset 후 stale output이 없는지 확인
12. 입력 수락 개수와 출력 완료 개수 일치

성공 시 마지막 줄은 다음 형식을 사용한다.

```text
PASS: tb_activation_int32_stream directed=<N> random=10000 stalls=<N>
```

## 10. 합성 및 타이밍 요구사항

```text
part: xc7z020clg400-1
clock: 10.000 ns
top: activation_int32_stream
Vivado: 2024.1
```

Acceptance 조건:

- simulation PASS
- 합성 error/critical warning 없음
- latch와 combinational loop 없음
- setup `WNS >= 0 ns`
- hold violation 없음
- ready/valid backpressure 경로 timing 통과
- multiplier가 불필요하게 transaction 수만큼 복제되지 않음

Utilization report에서 DSP48E1, LUT, FF 사용량과 no-stall latency를 기록한다.

## 11. 프로젝트 통합 규칙

모듈은 standalone이어야 하며 다음 모듈을 직접 instantiate하지 않는다.

- convolution/tile accumulator
- requantization
- parameter memory
- MaxPool
- AXI packer 또는 DMA wrapper

상위 모듈이 output channel에 맞는 mode와 slope parameter를 제공한다.

```text
tile accumulator valid/ready
→ activation_int32_stream
→ requant_int32_to_int8
→ optional maxpool2d_int8_tile
```

현재 `activation.v`를 즉시 삭제하지 않는다. 새 모듈을 독립 검증한 후 상위
pipeline 연결을 변경하고 기존 모듈을 정리한다.

## 12. 요청 범위에 포함하지 않는 기능

- Requantization 및 INT8 saturation
- BatchNorm folding
- slope parameter 생성 도구
- sigmoid, softmax
- MaxPool
- 1x1/3x3 convolution
- AXI packing/DMA
- activation parameter RAM

## 13. 제출 파일

```text
rtl/active/datapath/activation_int32_stream.v
rtl/tb/current/tb_activation_int32_stream.v
rtl/filelists/activation_tb.f
Python golden 또는 fixture 생성 파일
구현 메모/README
Vivado simulation PASS 로그
Vivado OOC utilization report
Vivado OOC timing summary
```

구현 메모에는 다음을 기록한다.

- no-stall latency와 initiation interval
- stall 처리 방식
- DSP/LUT/FF 사용량
- WNS/TNS
- random seed
- 알려진 제한사항

## 14. 완료 체크리스트

- [ ] LINEAR, LEAKY_RELU, RELU가 Python reference와 bit-exact하다.
- [ ] 0.1 slope가 RTL에 hard-code되어 있지 않다.
- [ ] 음수 exact-half rounding이 0에서 멀어지는 방향이다.
- [ ] INT32_MIN의 절댓값 처리에서 overflow가 없다.
- [ ] 잘못된 mode는 LINEAR로 동작하고 error를 표시한다.
- [ ] tag/last가 data와 정확히 정렬된다.
- [ ] output stall 동안 payload가 유지된다.
- [ ] reset 후 stale output이 없다.
- [ ] deterministic random 10,000개 이상을 통과한다.
- [ ] XC7Z020-1, 100 MHz에서 `WNS >= 0`이다.

위 항목이 모두 충족되어야 requantization 앞단에 통합한다.
