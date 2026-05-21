# 파일 경로 설정
weights_file_path = './layer3/layer3_conv_weights.txt'  # 가중치 파일의 경로를 입력하세요
output_prefix = 'layer3'  # 레이어 이름을 입력하세요

# 입력 채널과 출력 채널의 개수 설정
filter_size = 3  # 3x3 필터
input_channels = 16
output_channels = 32

# 가중치 파일 읽기
with open(weights_file_path, 'r') as file:
    weights = file.readlines()

# 문자열을 실수(float) 리스트로 변환
weights = [float(weight.strip()) for weight in weights]

# 가중치 분리: 3x3 필터, 16개의 입력 채널, 32개의 출력 채널에 맞게 나누기
for i in range(output_channels):
    start_index = i * filter_size * filter_size * input_channels
    end_index = (i + 1) * filter_size * filter_size * input_channels
    filter_weights = weights[start_index:end_index]
    
    # 가중치를 텍스트 파일로 저장
    output_file_path = f'./{output_prefix}/{output_prefix}_filter_{i+1}.txt'
    with open(output_file_path, 'w') as output_file:
        for weight in filter_weights:
            output_file.write(f"{weight}\n")

print(f"{output_channels}개의 필터가 각각 저장되었습니다.")
