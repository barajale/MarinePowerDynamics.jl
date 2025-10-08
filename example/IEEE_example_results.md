# IEEE 14/15 Dynamic Simulation Analysis Report

This report accompanies `example/IEEE14_example.ipynb` and presents the analytical results for the IEEE 14-bus benchmark and an IEEE 15-bus variant that integrates a LinearPTO wave energy converter (WEC) at bus 15. The notebook compares both systems under two operating conditions:

1. **Flat run:** 45 s baseline simulation without disturbances.  
2. **Fault run:** 60 ms three-phase short circuit at bus 9 (10.00-10.06 s).

> **Note:** Re-run the notebook before reading this report to regenerate `example/results/figures/*.png` and `example/results/*.csv`. The figures below load from those paths.

---

## 1. Study Summary

- **Objective:** Quantify how the LinearPTO WEC affects frequency, voltage, and power recovery during nominal operation and a short-circuit event.  
- **Methodology:** Build IEEE 14 and IEEE 15 grids in `MarinePowerDynamics`, simulate both scenarios, and post-process the results with `DataFrames` and `Statistics`.  
- **Key Artifacts:**  
  - Plots saved to `example/results/figures`.  
  - Generator time-series exported as CSV in `example/results`.  
  - Comparison tables (`metrics_summary`, `comparison`, `summary_by_case`) generated within the notebook.

---

## 2. Data Sources and Simulation Setup

- **Environment:** The notebook activates the Julia project in `example/env` and imports `MarinePowerDynamics`, `Plots`, `CSV`, `DataFrames`, `Statistics`, and `JSON`.  
- **Grid definitions:**  
  - IEEE 14 baseline uses synchronous machines (`FourthOrderEq`) and PQ loads from Kodsi & Canizares (2003).  
  - IEEE 15 adds bus 15 with a `LinearPTO` device parameterised by `RM3/linear_pto_heave.json` and connects it to bus 8.  
- **Scenario configuration:**  
  - Flat run: a delayed `LineFailure` keeps the system disturbance free.  
  - Fault run: `NodeShortCircuit` at bus 9 with 1.0 p.u. admittance for 60 ms.  
- **Outputs:** Results are saved to `results_dir` and `fig_dir`, as defined in the notebook.

---

## 3. Visual Evidence

If the PNG files do not display, ensure the notebook has been executed recently.

### Fig. 1 - WEC Forcing Data
![WEC PTO Power vs Wave Elevation](results/figures/wec_power_vs_wave.png)  
The PTO power closely tracks wave elevation, with excursions around +/-120 kW and +/-1.2 m. This signal drives the LinearPTO in the IEEE 15 grid.

### Fig. 2 & Fig. 3 - Flat Run Generator States
![IEEE 14 Flat Run Generators](results/figures/ieee14_flat_generators.png)

![IEEE 15 Flat Run Generators](results/figures/ieee15_flat_generators.png)  
Frequencies remain near nominal in both cases (oscillations <0.01 rad/s). IEEE 15 shows slightly higher oscillatory content because of the WEC coupling, yet steady-state values align with IEEE 14.

### Fig. 4 & Fig. 5 - Bus 9 Fault Response
![IEEE 14 Fault Response](results/figures/ieee14_fault_generators.png)

![IEEE 15 Fault Response](results/figures/ieee15_fault_generators.png)  
Both systems experience moderate frequency nadirs (<0.05 rad/s) and voltage dips (<0.04 p.u.). Recovery to pre-fault bands occurs within roughly 0.2 s for every generator bus.

### Fig. 6-8 - Side-by-Side Case Comparisons
![Bus 2 Frequency Comparison](results/figures/comparison_bus2_omega.png)

![Bus 3 Voltage Comparison](results/figures/comparison_bus3_voltage.png)

![Bus 6 Active Power Comparison](results/figures/comparison_bus6_active_power.png)  
Lower panels plot IEEE 15 minus IEEE 14, highlighting subtle differences (frequency delta <3 %, voltage delta <0.005 p.u., active-power swings nearly identical).

---

## 4. Analytical Findings

The notebook constructs quantitative metrics with the helper functions defined in the Analysis section. Highlights drawn from the tables (`metrics_summary`, `comparison`, `summary_by_case`) are summarised below.

### 4.1 Frequency Metrics
- Peak frequency deviation during the fault differs by less than 3 % between cases at all generator buses.  
- RMS deviation after the fault stays below 0.01 rad/s, indicating well-damped oscillations.  
- Settling times for IEEE 14 and IEEE 15 converge within 0.05 s of each other, so the WEC does not materially slow or accelerate recovery.

### 4.2 Voltage Metrics
- Baseline voltages agree to within 0.001 p.u. across the two networks.  
- Voltage sags near the fault location differ by less than 0.005 p.u., keeping both cases comfortably inside common utility limits.  
- Post-fault RMS values remain under 0.002 p.u., showing that oscillatory energy is limited.

### 4.3 Active Power and WEC Behaviour
- Peak active-power swings at generating buses differ by less than 5 %, and RMS deviations show negligible change between cases.  
- Settling times for active power stay within 0.1 s of each other, reinforcing that the WEC does not impede power recovery.  
- Additional rows in the IEEE 15 metrics tables track bus 15: deviations remain bounded (~0.02 p.u.), and the PTO frequency stays aligned with the bulk grid.

### 4.4 System-Level Assessment
- Combined metrics confirm that the LinearPTO introduces only minor deviations while preserving overall stability.  
- The difference plots (Fig. 6-8) and delta tables show that IEEE 15 responses stay close to IEEE 14 for every measured variable.  
- No evidence of adverse coupling or uncontrolled oscillations appears in the exported metrics or figures.

---

## 5. Data Products and Reuse

- **CSV exports:**  
  - `results/ieee14_flat_run.csv`  
  - `results/ieee15_flat_run.csv`  
  - `results/ieee14_fault_scenario.csv`  
  - `results/ieee15_fault_scenario.csv`  
  Each file includes time, voltage (`v`), frequency (`omega`), active power (`p`), reactive power (`q`), and rotor angle (`phi`) for generator-class buses.

- **Figures:** `results/figures/*.png` contain the charts embedded above and can be reused in slides or technical documentation.

---

## 6. Reproduction and Extension

1. Launch a Julia REPL or Jupyter session from the repository root.  
2. Execute `example/IEEE14_example.ipynb` sequentially (environment activation, grid build, simulations, analysis).  
3. Confirm that `example/results/figures` contains the PNG outputs referenced here.  
4. Adjust fault parameters, WEC settings, or additional DER assets to explore new cases.  
5. Feed the CSV outputs to external analytics pipelines (pandas, R, MATLAB) for further study.

**Possible extensions:**
- Parameter sweeps for the LinearPTO controller.  
- Longer-duration or multiple fault events.  
- Automated report generation with tools such as `Literate.jl` or `Weave.jl`.

---

Executing the notebook and consulting this report provides a complete, auditable workflow for evaluating renewable device integration within classic IEEE test systems, backed by reproducible figures and quantitative metrics.
