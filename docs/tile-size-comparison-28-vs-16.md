# 28×28 vs 16×16 타일 비교

## 결론

현재 단일 채널 3×3 accelerator에서는 **28×28을 기본 타일로 유지하는 편이 낫다.**

16×16은 타일 하나의 응답 시간이 57.01 µs에서 17.29 µs로 짧아지지만, 연산기와
weight RAM이 동일해서 FPGA 자원은 거의 줄지 않는다. 반대로 유효 출력 비율이 낮고
halo 중복과 타일 명령 횟수가 증가해 전체 feature map 처리량은 28×28보다 불리하다.

16×16은 낮은 단일-tile latency, 작은 DMA buffer, 세밀한 경계/ROI 작업이 중요한
실험용 대안으로 유지한다.

## 비교 조건

- Device: `XC7Z020CLG400-1`
- Tool: Vivado 2024.1
- Clock: 100 MHz, 10 ns, user uncertainty 0.2 ns
- Operation: IC=1, OC=1, valid 3×3 INT8 convolution, INT32 output
- MAC: 두 설계 모두 9개의 INT8 multiplier lane
- FIFO: 두 설계 모두 16-word output FIFO
- Simulation input: 동일한 수식, weight 9개, bias 1개
- Performance mode: 연속 AXIS input, `M_AXIS_TREADY=1`, parameter load 시간 제외
- Timing/resource: out-of-context place and route

## 기능 및 타일 규격

| 지표 | 28×28 | 16×16 |
| --- | ---: | ---: |
| 고정 AXI top | `top_single_conv_tile_axi` | `top_single_conv_tile_axi_16` |
| 입력 픽셀 | 784 | 256 |
| 유효 출력 크기 | 26×26 | 14×14 |
| 출력 픽셀 | 676 | 196 |
| 논리 line-buffer 저장량 | 84 byte | 48 byte |
| MM2S tile packet | 3136 byte | 1024 byte |
| S2MM tile packet | 2704 byte | 784 byte |
| 출력/입력 픽셀 비율 | 86.22% | 76.56% |
| 입력 픽셀/유효 출력 픽셀 | 1.160 | 1.306 |

두 설계 모두 인접 입력 타일 사이에 2픽셀 halo가 필요하다. 16×16은 타일 면적에서
halo가 차지하는 비율이 더 크다.

## 시뮬레이션 성능

AXI wrapper와 output FIFO를 포함한 결과이다.

| 지표 | 28×28 | 16×16 | 해석 |
| --- | ---: | ---: | --- |
| 타일 완료 cycle | 5703 | 1731 | 16×16이 69.6% 짧음 |
| 타일 latency @100 MHz | 57.01 µs | 17.29 µs | 단일 요청 응답은 16×16 우세 |
| cycle/output | 8.436 | 8.832 | 28×28이 4.5% 효율적 |
| output throughput | 11.858 Moutput/s | 11.336 Moutput/s | 28×28이 약 4.6% 높음 |
| 3×3 연산 환산 | 0.213 GOPS | 0.204 GOPS | multiply/add를 각각 1 op로 계산 |

현재 controller가 한 출력 결과를 기다린 다음 다음 window를 발행하므로 두 설계 모두
이론적인 1 output/cycle과는 거리가 있다. 이 병목은 타일 크기가 아니라 controller와
datapath issue 방식에 있다.

## XC7Z020 물리 구현 결과

| 지표 | 28×28 | 16×16 | 차이 |
| --- | ---: | ---: | ---: |
| WNS | +1.138 ns | +1.258 ns | 16×16이 +0.120 ns |
| TNS | 0.000 ns | 0.000 ns | 동일 |
| WHS | +0.011 ns | +0.009 ns | 둘 다 통과 |
| Setup failing endpoints | 0 | 0 | 동일 |
| Hold failing endpoints | 0 | 0 | 동일 |
| LUT | 1031 | 1020 | 16×16이 11개 감소 |
| FF | 705 | 691 | 16×16이 14개 감소 |
| LUTRAM | 42 | 42 | 동일 |
| RAMB18 | 9 | 9 | 동일 |
| DSP | 0 | 0 | 동일 |

논리 line buffer는 84 byte에서 48 byte로 작아지지만 FPGA primitive의 최소 단위 때문에
두 설계 모두 line buffer에 18 LUTRAM을 사용한다. 9개 weight read lane도 그대로라
RAMB18 사용량은 줄지 않는다. 따라서 총 절감은 LUT 약 1.1%, FF 약 2.0%에 불과하다.

두 설계의 최장 setup path는 모두 line buffer가 아니라 weight RAM에서 multiplier
stage register로 가는 경로이다.

- 28×28: 8.640 ns, 7 logic levels
- 16×16: 8.567 ns, 8 logic levels

## 416×416 출력 영역 예시

valid 3×3 결과 타일의 이동 간격을 각각 26과 14로 두고, 경계는 padding/crop한다고
가정한 단순 추정이다. PS 명령 시간과 DMA software overhead는 포함하지 않았다.

| 지표 | 28×28 | 16×16 |
| --- | ---: | ---: |
| 가로×세로 tile 수 | 16×16 | 30×30 |
| 총 tile 수 | 256 | 900 |
| 입력 픽셀 전송 | 200,704 | 230,400 |
| 입력 AXIS byte | 802,816 | 921,600 |
| 생성 출력 픽셀 | 173,056 | 176,400 후 crop |
| 추정 core/AXI cycle | 1,459,968 | 1,557,900 |
| 추정 시간 @100 MHz | 14.595 ms | 15.561 ms |

16×16은 28×28보다 타일 명령이 3.52배 많고 입력 전송량이 약 14.8% 많다. 순수 RTL
cycle 추정도 약 6.7% 느리며, 실제 PS/DMA software overhead를 포함하면 차이는 더
커질 가능성이 높다.

## 선택 기준

28×28을 선택할 조건:

- 전체 YOLO feature map 처리량이 우선
- PS 명령/DMA 횟수를 줄이고 싶음
- halo 중복을 줄이고 싶음
- 현재 보드 bring-up 기본 구성을 유지하고 싶음

16×16을 선택할 조건:

- 한 타일의 응답 latency가 중요
- 작은 ROI나 경계 조각을 자주 처리
- 1 KiB 입력 buffer 단위가 시스템 구조에 유리
- 향후 작은 타일 여러 개를 실제 병렬 core로 복제할 계획

현재처럼 core가 하나뿐인 구조에서는 16×16로 바꾸는 것만으로 병렬성이 늘어나지
않는다. 16×16의 작은 footprint를 성능으로 연결하려면 여러 tile core 복제 또는
controller의 다중-window issue가 추가로 필요하다.

## 재현 파일

- RTL: `rtl/pipeline_conv/top_single_conv_tile_16.v`
- AXI top: `rtl/pipeline_conv/top_single_conv_tile_axi_16.v`
- Fixture: `sw/fixture/single_conv_tile_16/`
- Functional TB: `rtl/filelists/tile_conv_16_tb.f`
- AXI TB: `rtl/filelists/tile_conv_16_axi_tb.f`
- Performance TB: `rtl/filelists/tile_conv_axi_perf_tb.f`
- 28×28 reports: `reports/tile_conv_ooc/`
- 16×16 reports: `reports/tile_conv_16_ooc/`
