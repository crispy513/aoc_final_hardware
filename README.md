# MESSAGE
- 在github上有兩個branch，一個是main(模擬測試)，一個是pe_syn(合成的資料)
- 重現DEMO方式:
1. cd bitmap_dla_end_roofline_profiler
2. make DEMO (會先跑沒有bitmap版本，再跑有bitmap版本)

# Environment

- aoc_2026_env docker environment
# Eyeriss DLA Experiments

這個 repository 目前主要包含兩組 DLA 實驗流程：

- `tvm_dla_end_to_end_test`: 從 ONNX/TVM 產生 runtime library、Relay graph、輸入資料，並跑 CPU/DLA end-to-end inference 測試。
- `bitmap_dla_roofline_profiler`: 比較 origin DLA 與 bitmap DLA backend，並產生 roofline、sparsity sweep 與 MNIST demo 相關分析結果。

所有指令以下都假設從對應資料夾內執行。



## tvm_dla_end_to_end_test

這個資料夾是一個 TVM 到 DLA/CPU runtime 的 end-to-end 測試流程。輸入模型位於：

```sh
model/alexnetbn_v2-power2.onnx
```

主要流程會產生：

- `output/lib_cpu.so`
- `output/lib_dla.so`
- `output/bin/input.bin`
- `output/relay/*.txt`
- `output/visu_VGG8_relay_ir*.svg`
- CPU/DLA testbench log 與 CSV profiling 結果

### Directory layout

- `Python/build_model.py`: 載入 ONNX model，經 TVM Relay flow 產生 runtime library、Relay dump 與 input binary。
- `Python/utils`: TVM build、Relay fusion、codegen、dataset generation helper。
- `Python/VisuTVM`: 將 Relay IR 轉成 SVG graph。
- `simulation/hardware`: DLA RTL 與 Verilator library build flow。
- `simulation/software`: CPU/DLA runtime 與 HAL。
- `testbench/cpu`: CPU-only host inference testbench。
- `testbench/dla`: DLA Verilator inference testbench。
- `lab`: Valgrind Massif demo。
- `Csource`: host-side input parsing 與 utility code。
- `data`: CIFAR-10 dataset。

### Common commands

顯示 Makefile 內建說明：

```sh
make help
```

產生 TVM model artifacts、Relay dumps、runtime libraries 與 `input.bin`：

```sh
make build_model
```

跑一張圖片的 CPU-only smoke test：

```sh
make test_cpu
```

跑一張圖片的 DLA smoke test：

```sh
make test_dla
```

一次跑完整基本流程：

```sh
make all
```

產生 before-fusion Relay graph，並嘗試產生 after-fusion graph：

```sh
make visuTVM
```

只產生 before-fusion graph：

```sh
make visuTVM_origin
```

嚴格產生 after-fusion graph：

```sh
make visuTVM_pass
```

產生報告需要的主要 artifacts：

```sh
make homework
```

`homework` 會依序執行 model build、Relay visualization、CPU full test、Valgrind Massif profiling、`ms_print` report 與 DLA per-layer CSV dump。

### Test and profiling targets

CPU-only 跑全部 100 張測試圖片：

```sh
make test_cpu_full
```

CPU-only 單張 inference 搭配 Valgrind Massif：

```sh
make valgrind_cpu
```

將 CPU Massif output 轉成文字報告：

```sh
make ms_print_cpu
```

DLA inference 並輸出每層統計 CSV：

```sh
make test_dla_info
```

常見輸出位置：

- CPU full-test log: `testbench/cpu/log/out.log`
- CPU Massif raw output: `testbench/cpu/massif_out/massif.out.*_main`
- CPU Massif text report: `testbench/cpu/massif_out/massif_output.txt`
- DLA per-layer CSV: `testbench/dla/dla_info.csv`
- Relay graph SVG: `output/visu_VGG8_relay_ir*.svg`

### Options

顯示實際執行的 command：

```sh
make all QUIET=0
```

指定 CPU/DLA testbench 的 CIFAR-10 class 與 image index：

```sh
make -C testbench/cpu test CLASS=4 INDEX=9
make -C testbench/dla test CLASS=4 INDEX=9
```

打開 DLA profiling define：

```sh
make test_dla_info DLA_INFO=1
```

### Cleanup

清除 build/test artifacts：

```sh
make clean
```

清除 dataset：

```sh
make clean_data
```

產生 compilation database：

```sh
make compdb
```

格式化 C/C++ 與 Python source：

```sh
make format
```

## bitmap_dla_roofline_profiler

這個資料夾用來比較原始 DLA backend 與 bitmap DLA backend。流程包含：

- NutShell CPU Verilator library
- origin DLA Verilator library
- bitmap DLA Verilator library
- CPU original/improve runtime ELF
- DLA testbench cases
- roofline analysis
- sparsity sweep analysis
- MNIST demo image generation 與 demo run

### Directory layout

- `include`: HAL 與 runtime header。
- `src/hal`: CPU/DLA HAL implementation。
- `src/hardware/cpu`: NutShell RTL 與 Verilator build flow。
- `src/hardware/dla_origin`: 原始 DLA RTL。
- `src/hardware/dla_bitmap`: bitmap DLA RTL，包含 `Sparse/BitmapBuffer.sv`。
- `src/runtime/cpu`: RV64 bare-metal CPU runtime，分成 `original` 與 `improve`。
- `src/runtime/dla`: DLA runtime 與 driver。
- `src/host`: quantization helper。
- `test/cases`: case0、case1、case2 與 CPU fallback workload。
- `test/testbench/cpu`: NutShell CPU runtime testbench。
- `test/testbench/dla`: DLA case testbench、MNIST demo、roofline/sparsity CSV。
- `roofline.py`: 從 `roofline_data.csv` 畫 origin/bitmap roofline 圖。
- `plot_sweep.py`: 從 `sparsity_sweep_data.csv` 畫 sparsity sweep 圖。

### Common commands

顯示 Makefile 內建說明：

```sh
make help
```

建置 CPU 與 DLA 硬體 Verilator libraries、runtime 與 testbench：

```sh
make all
```

只建置 NutShell CPU Verilator library：

```sh
make hardware_cpu
```

只建置 DLA Verilator library：

```sh
make hardware_dla
```

建置 CPU runtime ELFs 與 CPU testbench：

```sh
make cpu
```

建置 DLA testbench：

```sh
make dla
```

### CPU runtime tests

跑所有 CPU cases，包含 original 與 improve：

```sh
make run_cpu
```

只跑 original CPU runtime：

```sh
make run_cpu_original
```

只跑 improve CPU runtime：

```sh
make run_cpu_improve
```

跑單一 case：

```sh
make run_cpu_case0
make run_cpu_case1
make run_cpu_case2
```

跑 fallback workloads：

```sh
make run_cpu_fallback_linear
make run_cpu_fallback_linear_relu
```

常用 CPU options：

```sh
make run_cpu_case0 IMPROVE=1
make run_cpu_case0 DIAG=1
make run_cpu_case0 TRACE=1
```

- `IMPROVE=1`: 使用 improve runtime，預設是 original。
- `DIAG=1`: 測試失敗時印出前 16 筆 mismatch。
- `TRACE=1`: 產生 trace。

### DLA tests

跑所有 DLA cases：

```sh
make run_dla
```

跑單一 DLA case：

```sh
make run_dla_case0
make run_dla_case1
make run_dla_case2
```

跑 CPU improve 與 DLA cases：

```sh
make run_all
```

常用 DLA options：

```sh
make run_dla DLA_HW=origin
make run_dla DLA_HW=bitmap
make run_dla USE_BITMAP_WRAPPER=1
make run_dla DLA_HW=bitmap IFMAP_BITMAP=1
make run_dla INFO=1
make run_dla DEBUG=1
make run_dla TRACE=1
```

- `DLA_HW=origin`: 使用原始 DLA backend。
- `DLA_HW=bitmap` 或 `USE_BITMAP_WRAPPER=1`: 使用 bitmap DLA backend。
- `IFMAP_BITMAP=1`: 在 bitmap backend 啟用 bitmap-compressed IFMAP。
- `INFO=1`: 輸出 DLA 統計資訊。
- `DEBUG=1`: 印出 HAL verbose log。
- `TRACE=1`: 啟用 FST trace。

DLA profiling CSV 會輸出到：

```sh
build/dla_info_case0.csv
build/dla_info_case1.csv
build/dla_info_case2.csv
```

### Roofline and sparsity analysis

比較 origin 與 bitmap backend，產生 roofline 資料與圖片：

```sh
make roofline
```

主要輸出：

- `test/testbench/dla/roofline_data.csv`
- `roofline_origin.png`
- `roofline_bitmap.png`

跑 sparsity sweep 並畫出分析圖：

```sh
make run_all_analysis
```

或只跑 sweep：

```sh
make sparsity_sweep
```

主要輸出：

- `test/testbench/dla/sparsity_sweep_data.csv`
- `sparsity_sweep_analysis.png`

`sparsity_sweep` 預設測試 sparsity level：

```text
0 10 20 30 40 50 60 70 80 90
```

### MNIST demo

產生 MNIST 測試圖片與 binary：

```sh
make generate
```

執行 origin 與 bitmap MNIST demo：

```sh
make DEMO
```

相關輸出位於：

- `test/testbench/dla/test_img.bin`
- `test/testbench/dla/test_img.png`
- `test/testbench/dla/baseline_stats.txt`

### Cleanup

清除全部 build artifacts：

```sh
make clean
```

只清硬體：

```sh
make clean_hw
make clean_hw_cpu
make clean_hw_dla
```

只清 runtime/testbench：

```sh
make clean_runtime
make clean_runtime_cpu
make clean_runtime_dla
```

## Notes

- 兩個流程都會產生大量 build artifacts、trace、CSV 與圖片；需要重新跑 profiling 時，建議先執行對應的 `clean` target。
- `tvm_dla_end_to_end_test/data` 內含 CIFAR-10 data batch，檔案較大；push 到遠端時如果遇到 RPC 或 connection reset，通常是 pack 太大或網路中斷造成。
- `bitmap_dla_roofline_profiler` 的部分 Makefile echo 訊息可能因原始檔案編碼而顯示亂碼，但 target 名稱與執行流程不受影響。
