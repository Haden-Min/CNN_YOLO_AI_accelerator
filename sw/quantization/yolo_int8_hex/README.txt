YOLOv3-tiny INT8 HEX — PYNQ-Z2

1. 데이터 출처와 순서
이미 양자화된 yolov3-tiny-416_full_integer_quant.tflite의 상수 가중치를 그대로 추출했다.
Darknet FP32 .weights를 다시 양자화하지 않는다. 기존 TFLite scale과 일치하는 INT8 값이다.
conv_00~conv_12는 TFLite CONV_2D 연산 순서이며 기존 quant-check.py의 conv_ordinal과 같다.
분기 때문에 Darknet cfg의 Conv 순서와 일부 다르다. manifest.json의 이름/shape/op index를 사용한다.
TFLite OHWI를 OIHW로 변환: [출력채널][입력채널][커널행][커널열]. 커널열이 가장 빠르다.
주소 = (((oc * IC) + ic) * KH + kh) * KW + kw.

2. 파일
hex/conv_XX/weights_oihw_int8.hex: 한 줄 2자리, signed INT8의 2의 보수 (FF=-1, 80=-128).
hex/conv_XX/bias_int32.hex: TFLite 원본 bias, 한 줄 8자리 2의 보수.
hex/conv_XX/bias_raw_mac_int32.hex: bias - input_zero_point * sum(weights), 출력채널당 1개.
hex/conv_XX/params_dma32.hex: 3x3 레이어만 생성. [OC][IC][10] 순서.
  각 패킷은 하위 8비트에 가중치가 들어간 32비트 워드 9개와 보정 bias 워드 1개.
  예: INT8 -1은 DMA에서 000000FF. bias -1은 FFFFFFFF.
hex/manifest.json: shape, tensor 이름, scale, zero-point, 파일 크기/해시, 연산 인덱스.
이 파일은 일반 ASCII HEX 메모리 형식이며 Intel HEX 주소 레코드 형식이 아니다.

3. PYNQ Python 사용
이 폴더를 보드로 복사한 뒤 같은 폴더에서:

    from pynq_hex_loader import load_layer, parameter_packet
    from pynq import allocate
    import numpy as np
    weights, bias, metadata = load_layer('hex', 0)
    packet = parameter_packet(weights, bias, output_channel=0, input_channel=0)
    buf = allocate(shape=(10,), dtype=np.uint32)
    buf[:] = packet

buf를 기존 smoke_test_single_conv.py의 parameter_buffer처럼 DMA에 전달한다.
각 출력채널마다 누적 상태를 초기화하고, REG_TOTAL_IC를 설정한다.
각 입력채널에 대해 파라미터 로드 → 해당 입력 타일 실행을 반복한다.
RTL은 최종 입력채널의 누적 결과에 bias를 한 번 더하므로 같은 보정 bias를 각 패킷에 넣는다.
전송 완료 뒤 buf.close()로 버퍼를 해제한다.
기존 smoke_test_single_conv.py의 load_vector는 10진수를 읽는다. 새 HEX에는 제공한 read_hex를 사용해야 한다.
4개의 INT8을 한 uint32에 압축하면 현재 RTL과 맞지 않는다.

4. RTL 시뮬레이션
8비트 signed 배열에는 weights_oihw_int8.hex를 $readmemh로 읽을 수 있다.
32비트 bias 배열에는 해당 bias HEX를 읽는다. 실제 보드에는 PS 로더와 DMA 전송이 필요하다.

5. 계산 조건
현재 RTL의 raw qx*qw 누적에는 보정 bias를 쓴다.
입력에서 zero-point를 이미 뺀 경우에는 원본 bias를 써야 하며 중복 보정하면 안 된다.
이미지 경계의 실수 0 패딩은 양자화 입력의 input_zero_point 값으로 채워야 한다.
현재 RTL은 OC=1씩 처리하는 3x3 타일 연산이다. 1x1의 원본 HEX는 제공하지만 DMA 패킷은 생성하지 않는다.
전체 YOLO 실행에는 타일/출력채널 스케줄링, 1x1, pooling, route/concat, upsample 및 검출 후처리가 별도로 필요하다.
재양자화 multiplier/shift와 LeakyReLU 파라미터는 기존 requant_output을 함께 사용한다.
이 HEX 생성은 기존 fusion의 TFLite bit-exact 여부를 변경하거나 보장하지 않는다.

6. 재생성
    pip install numpy tflite flatbuffers
    python export_tflite_hex.py --model yolov3-tiny-416_full_integer_quant.tflite --output-dir hex

검증 결과는 verification.txt에 기록되어 있다. 실제 PYNQ-Z2 전송/실행 검증은 수행하지 않았다.
