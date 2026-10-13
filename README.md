# Windows Battery Health Checker

A small PowerShell script that generates a Windows battery report and prints your battery's **health percentage**:

```
Health % = Full Charge Capacity / Design Capacity × 100
```

Windows already collects both numbers in `powercfg /batteryreport`, but they are buried in an HTML file and you have to do the math yourself. This script runs the report, reads the values, and shows the result in one step.

## Example output

```
Generating battery report...

Battery        : DELL 0P3TJYK
Design capacity: 64,007 mWh
Full charge    : 37,924 mWh
Battery health : 59.25%
Capacity lost  : 40.75%
```

The health line is colored for a quick read:

| Health    | Color  |
|-----------|--------|
| 80% +     | Green  |
| 60% – 79% | Yellow |
| below 60% | Red    |

## Requirements

- Windows 10 or 11 (a laptop or tablet with a battery)
- PowerShell 5.1 or newer (built into Windows)
- No administrator rights needed
- Windows display language set to **English** (see [Limitations](#limitations))

## Usage

Download `battery-health.ps1`, open PowerShell in the folder that contains it, and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\battery-health.ps1
```

`-ExecutionPolicy Bypass` applies only to this one run, so you don't have to change your system's script policy.

### Options

| Parameter       | Description                                                              | Default                                |
|-----------------|--------------------------------------------------------------------------|----------------------------------------|
| `-ReportPath`   | Where to write and read the HTML battery report                          | `%USERPROFILE%\battery-report.html`    |
| `-UseExisting`  | Read an existing report instead of generating a new one                  | off                                    |

Examples:

```powershell
# Save the report somewhere else
.\battery-health.ps1 -ReportPath "D:\reports\battery.html"

# Re-use a report you already generated
.\battery-health.ps1 -UseExisting
```

## How it works

1. Runs `powercfg /batteryreport /output <path>` to create a fresh report.
2. Reads the HTML and pulls the **Design capacity** and **Full charge capacity** values from the "Installed batteries" section.
3. Calculates the health percentage and the share of capacity lost, then prints it.

If your device has more than one battery, each one is reported separately.

## Reading the result

- **Design capacity** is what the battery could hold when it was new.
- **Full charge capacity** is what it can hold today. It falls as the battery ages and goes through charge cycles.
- A battery is commonly considered worn out when health drops to roughly 50–60%, but this depends on the manufacturer and how you use the device. If runtime is no longer enough for your needs, replacing the battery is reasonable.

The full report (`battery-report.html`) also shows capacity history over time and recent usage, which helps you see how quickly the battery is degrading.

## Limitations

- The script reads the English labels in the report (`DESIGN CAPACITY`, `FULL CHARGE CAPACITY`). On a Windows installation using another display language, `powercfg` writes translated labels and the script will report that it could not find the values.
- It depends on the layout of the HTML report that `powercfg` produces. If a future Windows version changes that layout, the parsing may need updating.
- Desktops without a battery have nothing to report; `powercfg` will not list an installed battery.

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| "running scripts is disabled on this system" | Run it with `-ExecutionPolicy Bypass` as shown above |
| "Could not find DESIGN CAPACITY / FULL CHARGE CAPACITY" | Open the generated HTML report and check the labels are in English, then open an issue with the relevant section of the report |
| `powercfg failed` | Make sure the device has a battery and try again from a normal PowerShell window |

## Contributing

Issues and pull requests are welcome. If the parsing fails on your machine, please include the "Installed batteries" section of your `battery-report.html` with the serial number removed.

## License

Choose a license for your repository (for example MIT) and add a `LICENSE` file.
