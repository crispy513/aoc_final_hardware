# 合成指令說明

這份 README 說明如何使用本專案的參數化 Synopsys Design Compiler 合成流程。

本合成流程使用同一份 Tcl script。執行時透過 Makefile 指定 top module 名稱、RTL source file list，以及可選的輸出檔名前綴。

---

## 常用 Shortcut

| 指令 | Top module | 主要 RTL | 輸出前綴 |
|---|---|---|---|
| `make synthesize_PE` | `PE` | `src/PE_array/PE.sv` | `PE` |
| `make synthesize_PE_ori` | `PE_ori` | `src/PE_array/PE_origin.sv` | `PE_ori` |
| `make synthesize_PE_LEE` | `PE_LEE` | `src/PE_array/PE_LEE.sv` | `PE_LEE` |
| `make synthesize_PE_array` | `PE_array` | `src/PE_array/GIN/*`, `src/PE_array/GON/*`, `src/PE_array/PE_LEE.sv`, `src/PE_array/PE_array.sv` | `PE_array` |

以上 target 都會呼叫同一套參數化合成流程。

---

## 環境與限制條件

- 合成工具：Synopsys Design Compiler (`dc_shell`)，使用 CAD/CIC Synopsys 環境。
- Timing/power 工具：Synopsys PrimeTime (`pt_shell`) `W-2024.09-SP2`。
- Constraint file：`script/DC.sdc`。
- Clock constraint：`clk_period = 2 ns`，duty cycle 50%。
- DC setup file：`script/synopsys_dc.setup`。
- PT setup file：`script/synopsys_pt.setup`。
- Process/library：N16ADFP standard cell libraries，包含 `N16ADFP_StdCellss0p72v125c.db` 與 `N16ADFP_StdCellff0p88vm40c.db`。
- 工作目錄：`build/`。
- 輸出目錄：`syn/`。

---

## 基本指令

```bash
make synthesize SYN_TOP=<top_module> SYN_SRC="<rtl_files>" SYN_OUT=<output_prefix>
```

### 參數

| 參數 | 是否必填 | 說明 |
|---|---:|---|
| `SYN_TOP` | 是 | 要 elaborate 與 synthesize 的 top module 名稱。 |
| `SYN_SRC` | 通常是 | RTL source file 或 source file list。 |
| `SYN_OUT` | 否 | 輸出檔名前綴。若未指定，預設使用 `SYN_TOP`。 |

---

## 路徑規則

Makefile 會在 `build/` 目錄中執行 Design Compiler。

RTL 路徑以 project root 為基準傳入，例如 `src/...`。Tcl script 會在 `build/` 內自動解析這些路徑。

標準寫法：

```bash
make synthesize SYN_TOP=PE SYN_SRC=src/PE_array/PE.sv
```

也可以接受：

```bash
make synthesize SYN_TOP=PE SYN_SRC=../src/PE_array/PE.sv
```

---

## 範例指令

### 合成 `PE`

```bash
make synthesize_PE
```

等價的一般指令：

```bash
make synthesize SYN_TOP=PE SYN_SRC=src/PE_array/PE.sv SYN_OUT=PE
```

會產生：

```text
syn/PE_timing_max_50_rpt.txt
syn/PE_timing_min_50_rpt.txt
syn/PE_timing_max_no_rst_rpt.txt
syn/PE_area_rpt.txt
syn/PE_power_rpt.txt
syn/PE_syn.v
syn/PE_syn.sdf
syn/PE_syn.sdc
```

---

### 合成 `PE_ori`

```bash
make synthesize_PE_ori
```

等價的一般指令：

```bash
make synthesize SYN_TOP=PE_ori SYN_SRC=src/PE_array/PE_origin.sv SYN_OUT=PE_ori
```

會產生：

```text
syn/PE_ori_timing_max_50_rpt.txt
syn/PE_ori_timing_min_50_rpt.txt
syn/PE_ori_timing_max_no_rst_rpt.txt
syn/PE_ori_area_rpt.txt
syn/PE_ori_power_rpt.txt
syn/PE_ori_syn.v
syn/PE_ori_syn.sdf
syn/PE_ori_syn.sdc
```

---

### 合成 `PE_LEE`

```bash
make synthesize_PE_LEE
```

等價的一般指令：

```bash
make synthesize SYN_TOP=PE_LEE SYN_SRC=src/PE_array/PE_LEE.sv SYN_OUT=PE_LEE
```

會產生：

```text
syn/PE_LEE_timing_max_50_rpt.txt
syn/PE_LEE_timing_min_50_rpt.txt
syn/PE_LEE_timing_max_no_rst_rpt.txt
syn/PE_LEE_area_rpt.txt
syn/PE_LEE_power_rpt.txt
syn/PE_LEE_syn.v
syn/PE_LEE_syn.sdf
syn/PE_LEE_syn.sdc
```

---

### 合成 `PE_array`

使用 shortcut target 時，Makefile 會自動帶入所需的 GIN/GON/PE source file list：

```bash
make synthesize_PE_array
```

會產生：

```text
syn/PE_array_timing_max_50_rpt.txt
syn/PE_array_timing_min_50_rpt.txt
syn/PE_array_timing_max_no_rst_rpt.txt
syn/PE_array_timing_GIN_rpt.txt
syn/PE_array_timing_GON_rpt.txt
syn/PE_array_area_rpt.txt
syn/PE_array_power_rpt.txt
syn/PE_array_syn.v
syn/PE_array_syn.sdf
syn/PE_array_syn.sdc
```

如果要手動傳入多個 RTL 檔案，請用引號包住整個 file list：

```bash
make synthesize SYN_TOP=PE_array SYN_SRC="src/PE_array/GIN/GIN_MulticastController.sv src/PE_array/GIN/GIN_Bus.sv src/PE_array/GIN/GIN.sv src/PE_array/GON/GON_MulticastController.sv src/PE_array/GON/GON_Bus_full_throughput_pipeline.sv src/PE_array/GON/GON_full_throughput_pipeline.sv src/PE_array/PE_LEE.sv src/PE_array/PE_array.sv" SYN_OUT=PE_array
```

---

## 輸出命名規則

輸出檔名前綴由 `SYN_OUT` 控制。

如果沒有指定 `SYN_OUT`，script 會使用 `SYN_TOP` 作為輸出前綴。

例如：

```bash
make synthesize SYN_TOP=PE SYN_SRC=src/PE_array/PE.sv
```

等價於：

```bash
make synthesize SYN_TOP=PE SYN_SRC=src/PE_array/PE.sv SYN_OUT=PE
```

產生的檔案會依照以下命名規則：

```text
syn/${SYN_OUT}_timing_max_50_rpt.txt
syn/${SYN_OUT}_timing_min_50_rpt.txt
syn/${SYN_OUT}_timing_max_no_rst_rpt.txt
syn/${SYN_OUT}_timing_GIN_rpt.txt
syn/${SYN_OUT}_timing_GON_rpt.txt
syn/${SYN_OUT}_area_rpt.txt
syn/${SYN_OUT}_power_rpt.txt
syn/${SYN_OUT}_syn.v
syn/${SYN_OUT}_syn.sdf
syn/${SYN_OUT}_syn.sdc
```

---

## 注意事項

- `build/` 是工具產生的工作目錄，不納入版本控制。
- `syn/` 內是合成產生的 report、netlist、SDF 與 SDC；版本控制中僅保留需要繳交或比較的結果。
- Design Compiler 執行時如果印出 Tcl commands，屬於正常現象。
- 如果合成失敗，請優先檢查實際 error message，常見原因包含 source path 錯誤或 Makefile 變數未設定。
