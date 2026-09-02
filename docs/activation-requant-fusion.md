# Activation과 INT8 Requantization 융합 설계

## 설계 결정

3단계 출력 경로에서는 독립적인 `activation_requant_int8_stream` 모듈 하나를 사용한다. 이 모듈은 선택된 활성화 함수와 signed INT32→INT8 requantization을 결합하며, 양수와 음수 경로가 하나의 곱셈기를 공유한다.

실행 중 선택할 수 있는 모드는 YOLOv3-Tiny의 합성곱 계층에서 사용하는 활성화 함수로 제한한다.

| `activation_mode_i` | 동작 |
| --- | --- |
| `2'b00` | `LINEAR` |
| `2'b01` | `LEAKY_RELU` |
| `2'b10`, `2'b11` | 예약값. `LINEAR`로 계산하고 `mode_error_o`를 1로 출력 |

ReLU와 그 밖의 활성화 함수는 이 모듈의 구현 범위에 포함하지 않는다.

## 배치 위치

현재 타일 설계는 입력 채널을 순차적으로 처리한다. 따라서 각 입력 채널의 합성곱 결과에 활성화 함수를 적용하면 안 된다. 모든 입력 채널의 누산과 bias 덧셈이 끝난 뒤의 최종 INT32 값에 활성화 함수와 requantization을 적용해야 한다.

```text
top_single_conv_tile
  → tile_psum_buffer
  → activation_requant_int8_stream
  → INT8-to-AXI-word adapter
  → axis_output_fifo
```

기존 `conv_datapath` 내부의 활성화 기능은 비활성화 상태로 유지한다. 이 위치에서 Leaky ReLU를 적용하면 입력 채널 전체를 합산한 `Leaky(a + b)`가 아니라 `Leaky(a) + Leaky(b)`를 계산하게 되어 올바른 합성곱 결과가 나오지 않는다.

## 산술 규격

상위 로직은 양수용과 음수용 고정소수점 requantization 계수를 제공한다.

```text
positive_real_scale ≈ multiplier_pos / 2^shift_pos
negative_real_scale ≈ multiplier_neg / 2^shift_neg
```

`LINEAR` 모드에서는 누산값의 부호와 관계없이 양수용 계수를 사용한다. `LEAKY_RELU` 모드에서는 누산값이 음수일 때 음수용 계수를 사용한다. 오프라인 계수 생성 도구는 Leaky ReLU의 음수 기울기를 음수용 계수에 미리 반영한다.

```text
positive_real_scale = input_scale × weight_scale / output_scale
negative_real_scale = 0.1 × positive_real_scale
```

데이터 경로는 다음 연산을 수행한다.

```text
product = signed_int64(acc × selected_multiplier)
scaled  = round_to_nearest_away_from_zero(product / 2^selected_shift)
shifted = scaled + zero_point
output  = clamp(shifted, -128, 127)
```

이 모듈은 특정 모델의 scale 값이나 0.1을 RTL에 하드코딩하지 않는다. 양수용·음수용 계수는 오프라인에서 각각 생성한다. 이렇게 해야 두 계수의 정수 근사값을 독립적으로 선택하고 근사 오차를 줄일 수 있다.

## 스트림 인터페이스 규칙

모든 입력값은 `valid_i && ready_o`가 1인 사이클에만 받아들인다. 받아들인 데이터는 입력 순서대로 정확히 한 번 출력한다. `valid_o=1 && ready_i=0`인 동안에는 data, status, tag, last와 valid를 모두 안정적으로 유지한다.

구현은 전체 파이프라인을 동시에 정지할 수 있는 7개 stage로 구성한다.

1. 입력 수락 및 계수 선택
2. Signed 32×32 곱셈
3. 곱셈 결과의 부호 및 절댓값 변환
4. 반올림 보정값 덧셈
5. 가변 right shift
6. 곱셈 결과의 부호 복원
7. Zero point 덧셈, INT8 saturation 및 출력 유지

stall이 없을 때 입력을 받은 시점부터 `valid_o`가 1이 될 때까지의 latency는 6사이클이고, 입력 간격은 1사이클이다. 즉 파이프라인이 채워진 뒤에는 매 사이클 결과 하나를 출력할 수 있다. 뒤쪽 모듈에서 stall이 발생하면 전체 파이프라인을 정지하고 `ready_o`를 통해 앞쪽 모듈로 역압을 전달한다.

## 외부 파라미터 연결

AXI register, parameter packet 및 parameter RAM은 외부 제어·파라미터 로직의 책임이며 이 모듈에서는 수정하지 않는다. 외부 로직은 현재 출력 채널에 해당하는 다음 값을 제공해야 한다.

- `activation_mode_i`
- `multiplier_pos_i`, `shift_pos_i`
- `multiplier_neg_i`, `shift_neg_i`
- `zero_point_i`

이 값들은 해당 누산 결과와 함께 전달되어야 한다. 구체적인 전달 방식은 AXI·제어 로직 담당자와 협의해서 결정한다. 현재 사용 중인 weight/bias 10-word packet은 이번 작업에서 변경하지 않는다.

초기 AXI 통합에서는 INT8 결과 하나를 32비트 word 하나에 넣는다.

```text
TDATA[7:0]  = signed INT8의 two's-complement bit pattern
TDATA[31:8] = 0
```

## 관련 파일과 검증 방법

```text
rtl/pipeline_conv/activation_requant_int8_stream.v
rtl/tb/tb_activation_requant_int8_stream.v
rtl/filelists/activation_requant_tb.f
sw/quantization/activation_requant_reference.py
```

저장소 최상위 디렉터리에서 Python 기준 모델의 자체 검사를 실행한다.

```powershell
python sw/quantization/activation_requant_reference.py --self-test
```

Vivado 2024.1에서는 다음 명령으로 RTL 테스트를 실행한다.

```powershell
& "D:\Vivado\2024.1\bin\xvlog.bat" -f rtl/filelists/activation_requant_tb.f
& "D:\Vivado\2024.1\bin\xelab.bat" tb_activation_requant_int8_stream -s activation_requant_sim
& "D:\Vivado\2024.1\bin\xsim.bat" activation_requant_sim -runall
```

기존 `rtl/pipeline_conv/activation.v`는 더 이상 사용하지 않는 파일로 표시한 채 유지한다. 이후 `conv_datapath`의 activation 인스턴스와 모든 filelist 참조를 함께 제거하고 기존 회귀 테스트가 통과한 뒤 해당 파일을 삭제한다.

## 검증 결과

Vivado 2024.1로 수행한 검증 결과는 다음과 같다.

```text
RTL simulation: PASS
  directed vectors: 10
  randomized vectors: 1000
  randomized downstream stalls: enabled

Python reference self-test: PASS
  directed vectors: 8
  randomized vectors: 10000
  seed: 20260820

XC7Z020CLG400-1 out-of-context route, 10 ns clock:
  WNS: +2.518 ns
  TNS:  0.000 ns
  Slice LUTs:      671
  Slice Registers: 496
  DSP48E1:           4
```

RTL에는 signed 32×32 곱셈 연산이 하나 존재한다. Vivado는 이 연산을 7-series FPGA에서 DSP48E1 네 개로 구성한다.

위 timing 결과는 융합 모듈만 따로 합성한 out-of-context 결과다. 누산기, 파라미터 공급 로직 및 AXI 출력 경로와 연결한 뒤 전체 시스템 timing을 다시 확인해야 한다.
