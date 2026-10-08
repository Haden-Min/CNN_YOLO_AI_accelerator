# YOLOv3-tiny INT8 HEX 사용 안내

양자화된 YOLOv3-tiny 모델에서 추출한 가중치를 **PYNQ-Z2 프로젝트의 현재 RTL**에 전달하기 위한 파일 모음입니다.

## 1. 데이터 출처

`yolov3-tiny-416_full_integer_quant.tflite`에 저장된 INT8 상수 가중치를 그대로 추출했습니다. 기존 모델의 scale에 대응하는 값을 사용합니다.

- **레이어 수:** Conv 13개
- **가중치 수:** 8,845,488개
- **레이어 번호:** `conv_00` ~ `conv_12`

레이어 번호는 TFLite의 `CONV_2D` 연산 순서이며, 기존 `yolov3-tiny-quant-check.py`의 `conv_ordinal`과 같습니다. 분기 때문에 Darknet `.cfg`의 Conv 순서와 일부 다르므로, 레이어 대응은 `hex/manifest.json`의 텐서 이름·shape·연산 인덱스를 기준으로 확인하세요.

## 2. 파일 구성

| 파일 | 내용 | 한 줄의 형식 |
|---|---|---|
| `hex/conv_XX/weights_oihw_int8.hex` | OIHW 순서의 가중치 | 8비트, 16진수 2자리 |
| `hex/conv_XX/bias_int32.hex` | TFLite 원본 bias | 32비트, 16진수 8자리 |
| `hex/conv_XX/bias_raw_mac_int32.hex` | 입력 zero-point를 보정한 bias | 32비트, 16진수 8자리 |
| `hex/conv_XX/params_dma32.hex` | 현재 RTL용 파라미터 패킷. 3×3 레이어만 제공 | 32비트, 16진수 8자리 |
| `hex/manifest.json` | shape, 텐서 이름, scale, zero-point, 워드 수·비트 폭·해시, 연산 인덱스 | JSON |
| `export_tflite_hex.py` | 모델에서 HEX를 추출하는 코드 | Python |
| `pynq_hex_loader.py` | HEX 로딩 및 DMA 패킷 구성 코드 | Python |
| `verification.txt` | 검증 결과 | 텍스트 |

HEX는 **한 줄에 한 워드를 기록한 ASCII 16진수 형식**입니다. 주소 레코드를 포함하는 Intel HEX 형식은 아닙니다. 음수는 2의 보수로 저장합니다.

| 값 | 8비트 가중치 HEX | DMA의 32비트 가중치 워드 |
|---|---|---|
| 1 | `01` | `00000001` |
| -1 | `FF` | `000000FF` |
| -128 | `80` | `00000080` |

32비트 bias 값 `-1`은 `FFFFFFFF`입니다.

## 3. 가중치 저장 순서: OIHW

TFLite의 **OHWI** 배열을 다음 **OIHW** 순서로 변환했습니다.

```text
[출력채널][입력채널][커널행][커널열]
    O         I        H        W
```

현재 RTL이 한 입력 채널의 3×3 가중치 9개를 연속으로 받아 계산하므로, 해당 커널을 연속된 주소에 배치한 것입니다. 가중치 값은 유지하고 저장 순서만 바꿉니다.

**커널열이 가장 빠르다**는 것은 다음 주소로 갈 때 열부터 바뀐다는 뜻입니다.

```text
(행, 열): (0,0) → (0,1) → (0,2) → (1,0) → … → (2,2)
```

인덱스가 모두 0부터 시작할 때 가중치 파일의 주소는 다음과 같습니다.

```text
주소 = (((oc * IC) + ic) * KH + kh) * KW + kw

     = oc * (IC * KH * KW)
     + ic * (KH * KW)
     + kh * KW
     + kw
```

| 기호 | 의미 |
|---|---|
| `oc`, `ic` | 현재 출력·입력 채널 인덱스 |
| `kh`, `kw` | 현재 커널 행·열 인덱스 |
| `IC` | 입력 채널 수 |
| `KH`, `KW` | 커널 높이·너비 |

예를 들어 입력 채널이 3개이고 커널이 3×3이면:

| 출력 채널 | 입력 채널 | 가중치 주소 |
|---|---|---|
| 0 | 0 | 0~8 |
| 0 | 1 | 9~17 |
| 0 | 2 | 18~26 |
| 1 | 0 | 27~35 |

이 주소식은 `weights_oihw_int8.hex`에 적용됩니다. Bias 워드가 삽입되는 DMA 패킷 파일은 아래의 패킷 구조를 따릅니다.

## 4. DMA 패킷 구조

`params_dma32.hex`는 **[출력채널][입력채널][10워드]** 순서입니다.

| 패킷 내 위치 | 내용 |
|---|---|
| 워드 0~8 | 한 입력 채널의 3×3 가중치. 각 32비트 워드의 하위 8비트 사용 |
| 워드 9 | 해당 출력 채널의 보정 bias. 32비트 전체 사용 |

현재 RTL은 **가중치 하나당 32비트 워드 하나**를 받습니다. INT8 가중치 4개를 한 워드에 압축하는 방식과는 다릅니다.

## 5. PYNQ Python에서 사용하기

이 폴더를 보드로 복사한 뒤, 같은 폴더에서 다음과 같이 버퍼를 준비합니다.

```python
from pynq_hex_loader import load_layer, parameter_packet
from pynq import allocate
import numpy as np

# conv_00의 가중치, 보정 bias, 메타데이터
weights, bias, metadata = load_layer("hex", 0)

# 출력 채널 0, 입력 채널 0에 해당하는 10워드 패킷
packet = parameter_packet(
    weights,
    bias,
    output_channel=0,
    input_channel=0,
)

buf = allocate(shape=(10,), dtype=np.uint32)
buf[:] = packet
```

이 코드는 **전송 버퍼 준비까지** 수행합니다. 실제 전송에는 Overlay, DMA 및 가속기 제어가 필요합니다.

1. 각 출력 채널마다 누적 상태를 초기화하고 `REG_TOTAL_IC`를 설정합니다.
2. 각 입력 채널에 대해 **파라미터 로드 → 해당 입력 타일 실행**을 반복합니다.
3. 최종 입력 채널의 결과를 수신합니다.
4. 버퍼를 사용하는 모든 전송이 완료되면 `buf.close()`로 해제합니다.

RTL은 최종 입력 채널의 누적 결과에 bias를 한 번 더합니다. 따라서 같은 출력 채널의 모든 입력 채널 패킷에 동일한 보정 bias를 넣습니다.

### 기존 `smoke_test_single_conv.py`와의 관계

`sw/pynq/smoke_test_single_conv.py`는 프로젝트에 이미 있던 **보드 동작 확인 프로그램**입니다. Bitstream을 로드하고, DMA로 테스트 데이터를 전달한 뒤, 계산 결과를 정답과 비교합니다. 전체 YOLO 추론 프로그램은 아닙니다.

이 파일의 `parameter_buffer` 전송 및 제어 순서를 참고하면 됩니다. 다만 기존 `load_vector`는 확장자가 `.hex`인 파일을 **10진수로 읽습니다**. 이번에 제공한 실제 16진수 HEX는 `pynq_hex_loader.py`의 `read_hex` 또는 이를 사용하는 `load_layer`로 읽어야 합니다.

## 6. Bias와 패딩 처리

보정 bias는 출력 채널마다 다음과 같이 계산합니다.

```text
보정 bias = 원본 bias - input_zero_point × 해당 출력 채널의 전체 가중치 합
```

| 하드웨어의 MAC 연산 | 사용할 bias |
|---|---|
| 원본 정수 `qx × qw` 누적 | `bias_raw_mac_int32.hex` |
| 입력에서 zero-point를 뺀 `(qx - zx) × qw` 누적 | `bias_int32.hex` |

입력과 bias에서 zero-point를 중복 보정하면 안 됩니다.

이미지 경계에서 **실수 0을 나타내는 패딩 값은 입력의 `input_zero_point`**입니다. 양자화된 입력 타일의 경계를 이 값으로 채워야 합니다.

## 7. RTL 시뮬레이션과 지원 범위

- 8비트 signed 배열에는 `weights_oihw_int8.hex`를 `$readmemh`로 읽을 수 있습니다.
- 32비트 bias 배열에는 필요한 bias HEX를 읽습니다.
- 실제 보드에서는 PS 측 로더와 DMA 전송이 필요합니다.

현재 RTL은 **출력 채널 하나씩 처리하는 3×3 타일 연산**을 지원합니다. 1×1 레이어의 가중치 HEX도 제공하지만, 해당 레이어의 DMA 패킷은 생성하지 않았습니다.

전체 YOLO 실행에는 타일·출력 채널 스케줄링, 1×1 연산, pooling, route/concat, upsample, 검출 후처리가 별도로 필요합니다.

재양자화 multiplier/shift와 LeakyReLU 파라미터는 기존 `requant_output`을 함께 사용합니다. Conv와 LeakyReLU를 합칠 때 중간 INT8 반올림이 생략되는 기존 방식은 TFLite와 비트 단위로 동일한 결과를 보장하지 않습니다.

## 8. HEX 재생성

추출 코드를 실행할 Python 환경에 필요한 패키지를 설치합니다.

```shell
pip install numpy tflite flatbuffers
```

모델 경로와 출력 폴더를 지정해 실행합니다.

```shell
python export_tflite_hex.py --model yolov3-tiny-416_full_integer_quant.tflite --output-dir hex
```

## 9. 검증 결과

- 모든 HEX 파일을 다시 읽어 기록한 값과 순서가 보존되는지 확인했습니다.
- 동일한 모델 SHA256의 기존 양자화 JSON과 모든 출력 채널의 가중치 합, scale, 원본 bias, 보정 bias를 대조했습니다.
- 모든 3×3 DMA 파일의 워드가 OIHW 가중치 및 보정 bias와 일치하는지 확인했습니다.
- 파일 SHA256을 검증했습니다.

상세 결과는 `verification.txt`에 있습니다. **실제 PYNQ-Z2 전송 및 하드웨어 실행은 아직 검증하지 않았습니다.**
