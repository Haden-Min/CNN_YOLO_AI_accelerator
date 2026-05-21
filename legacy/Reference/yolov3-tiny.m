%%%%%%%%%%%%%%%%%%%
%% 이미지 전처리 %%
%%%%%%%%%%%%%%%%%%%

% 1. 데이터 로드
imageSize = [416, 416]; % 416x416 with padding
layer1NumFilters = 16; % layer 1 필터 수
epsilon = 1e-5;

% R, G, B 채널 로드
R = dlmread('freq/red_channel.txt');
G = dlmread('freq/green_channel.txt');
B = dlmread('freq/blue_channel.txt');

% 패딩 제거
R = R(2:end-1, 2:end-1);
G = G(2:end-1, 2:end-1);
B = B(2:end-1, 2:end-1);
% 하는 이유를 잘 모르겠음..

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Layer1 - convolution layer %%
%% 416x416x3 -> 416x416x16    %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% convolution &&

% 필터 데이터 로드 (size: 3x3)
R_filters = dlmread('freq/layer1/r_channel_weights.txt');
G_filters = dlmread('freq/layer1/g_channel_weights.txt');
B_filters = dlmread('freq/layer1/b_channel_weights.txt');

% 필터 4D 배열로 변환
R_filters = reshape(R_filters, [3, 3, 1, layer1NumFilters]);
G_filters = reshape(G_filters, [3, 3, 1, layer1NumFilters]);
B_filters = reshape(B_filters, [3, 3, 1, layer1NumFilters]);

% 2. Convolution 연산 수행
% 결과 저장을 위한 배열 초기화
conv_R = zeros(imageSize(1), imageSize(2), layer1NumFilters);
conv_G = zeros(imageSize(1), imageSize(2), layer1NumFilters);
conv_B = zeros(imageSize(1), imageSize(2), layer1NumFilters);

% 필터 적용
for i = 1:layer1NumFilters
    % R 채널
    conv_R(:,:,i) = conv2(R, R_filters(:,:,1,i),"same");
    % G 채널
    conv_G(:,:,i) = conv2(G, G_filters(:,:,1,i),"same");
    % B 채널
    conv_B(:,:,i) = conv2(B, B_filters(:,:,1,i),"same");
end

conv_result = conv_R + conv_G + conv_B;

%% batchnorm %%

layer1_mean = dlmread('freq\layer1\layer1_batchnorm_running_mean.txt');
layer1_var = dlmread('freq\layer1\layer1_batchnrom_running_var.txt');
layer1_gamma = dlmread('freq\layer1\layer1_batchnorm_weight.txt');
layer1_beta = dlmread('freq\layer1\layer1_batchnorm_biases.txt');

conv_result_bn = zeros(size(conv_result));

for i = 1:16
    conv_result_bn(:,:,i) = layer1_gamma(i) * (conv_result(:,:,i) - layer1_mean(i)) / sqrt(layer1_var(i) + epsilon) + layer1_beta(i);
end

% ReLU 연산 수행
conv_result_relu = max(conv_result_bn, 0);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Layer2 - Pooling Layer   %%
%% 416x416x16 -> 208x208x16 %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% 입력 데이터가 416x416x16 크기의 conv_result_relu라고 가정
input_data = conv_result_relu;

% 출력 크기 계산 (맥스풀링 후 크기는 입력 크기의 절반이 됨)
output_size = [size(input_data, 1)/2, size(input_data, 2)/2, size(input_data, 3)];

% 맥스풀링 결과를 저장할 배열 초기화
max_pooled_result = zeros(output_size);

% 맥스풀링 연산 수행
for k = 1:size(input_data, 3)  % 각 채널에 대해 수행
    for i = 1:2:size(input_data, 1)-1
        for j = 1:2:size(input_data, 2)-1
            % 현재 윈도우에서 최대값 찾기
            max_pooled_result((i+1)/2, (j+1)/2, k) = max(max(input_data(i:i+1, j:j+1, k)));
        end
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Layer3 - convolution layer %%
%% 208x208x16 -> 208x208x32   %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% 기본 설정
[input_height, input_width, input_channels] = size(max_pooled_result);  % 208x208x16
filter_size = 3;
output_channels = 32;

% 필터 데이터 로드 (가정: filters는 3x3x16x32의 크기로 저장되어 있음)
filters = zeros(filter_size, filter_size, input_channels, output_channels);
for i = 1:output_channels
    file_path = ['freq/layer3/layer3_filter_', num2str(i), '.txt'];
    filters(:,:,:,i) = reshape(dlmread(file_path), filter_size, filter_size, input_channels);
end

% 결과 저장을 위한 배열 초기화
conv_result = zeros(input_height, input_width, output_channels);

% 컨볼루션 연산 수행 (conv2 사용, 'same' 옵션으로 크기 유지)
for k = 1:output_channels
    conv_channel = zeros(input_height, input_width);
    for c = 1:input_channels
        conv_channel = conv_channel + conv2(max_pooled_result(:,:,c), filters(:,:,c,k), 'same');
    end
    conv_result(:,:,k) = conv_channel;
end

%% batchnorm %%

layer3_mean = dlmread('freq\layer3\layer3_batchnorm_running_mean.txt');
layer3_var = dlmread('freq\layer3\layer3_batchnorm_running_var.txt');
layer3_gamma = dlmread('freq\layer3\layer3_batchnorm_weights.txt');
layer3_beta = dlmread('freq\layer3\layer3_batchnorm_biases.txt');

conv_result_bn = zeros(size(conv_result));

for i = 1:32
    conv_result_bn(:,:,i) = layer3_gamma(i) * (conv_result(:,:,i) - layer3_mean(i)) / sqrt(layer3_var(i) + epsilon) + layer3_beta(i);
end

% ReLU 연산 수행
conv_result_relu = max(conv_result_bn, 0);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Layer4 - Pooling Layer   %%
%% 208x208x32 -> 104x104x32 %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% 입력 데이터가 416x416x16 크기의 conv_result_relu라고 가정
input_data = conv_result_relu;

% 출력 크기 계산 (맥스풀링 후 크기는 입력 크기의 절반이 됨)
output_size = [size(input_data, 1)/2, size(input_data, 2)/2, size(input_data, 3)];

% 맥스풀링 결과를 저장할 배열 초기화
max_pooled_result = zeros(output_size);

% 맥스풀링 연산 수행
for k = 1:size(input_data, 3)  % 각 채널에 대해 수행
    for i = 1:2:size(input_data, 1)-1
        for j = 1:2:size(input_data, 2)-1
            % 현재 윈도우에서 최대값 찾기
            max_pooled_result((i+1)/2, (j+1)/2, k) = max(max(input_data(i:i+1, j:j+1, k)));
        end
    end
end

disp(size(max_pooled_result));

%% 결과 확인

% 16개의 필터 결과를 4x4 그리드로 표시
figure;

% subplot을 사용해 4x4 그리드 생성
for i = 1:32
    subplot(8, 4, i);
    imshow(conv_result_relu(:,:,i), []);
    title(sprintf('%d', i));
end

