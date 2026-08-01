using System.Diagnostics;
using System.Text;

namespace RB.JavaConverter112;

public sealed class MainForm : Form
{
    private readonly RadioButton _radProject = new() { Text = "Mode A: Project folder (1.12 source / decompiled with src/)", AutoSize = true };
    private readonly RadioButton _radJar = new() { Text = "Mode B: Finished Forge 1.12.2 .jar (decompile + scaffold)", AutoSize = true, Checked = true };
    private readonly Label _lblInput = new() { Text = "Input .jar", AutoSize = true, ForeColor = Color.Gainsboro, Anchor = AnchorStyles.Left, Margin = new Padding(0, 10, 8, 4) };
    private readonly TextBox _txtInput = NewTextBox();
    private readonly TextBox _txtOutput = NewTextBox();
    private readonly TextBox _txtMc = NewTextBox();
    private readonly TextBox _txtNeo = NewTextBox();
    private readonly CheckBox _chkCompile = NewCheck("Compile after convert (optional; expect many 1.12 errors)", false);
    private readonly CheckBox _chkDry = NewCheck("Dry run (preview only)", false);
    private readonly CheckBox _chkContinueNeo = NewCheck("After decompile, also scaffold NeoForge 26.2", true);
    private readonly Button _btnBrowseIn = NewButton("Browse...", 110);
    private readonly Button _btnBrowseOut = NewButton("Browse...", 110);
    private readonly Button _btnRun = NewButton("Convert", 130);
    private readonly Button _btnOpenOut = NewButton("Open output", 130);
    private readonly Button _btnClear = NewButton("Clear log", 120);
    private readonly ProgressBar _progress = new() { Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 30, Height = 22, Dock = DockStyle.Fill, Visible = false };
    private readonly RichTextBox _log = new();
    private Process? _running;
    private bool _busy;

    public MainForm()
    {
        Text = "RB 1.12 → 26.2 Java Converter v0.2.0";
        ClientSize = new Size(980, 720);
        MinimumSize = new Size(840, 600);
        StartPosition = FormStartPosition.CenterScreen;
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { /* optional */ }
        BackColor = Color.FromArgb(32, 34, 40);
        ForeColor = Color.Gainsboro;
        Font = new Font("Segoe UI", 9.5f);
        Padding = new Padding(12);

        var header = new Label
        {
            Text = "Forge 1.12.2 jar/project → NeoForge 26.2 scaffold (experimental)",
            Font = new Font("Segoe UI Semibold", 12f),
            ForeColor = Color.White,
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 4)
        };
        var sub = new Label
        {
            Text = "Separate from Legacy 1.20.1/1.21 converter. Scaffold only — large mods need heavy manual work.",
            ForeColor = Color.FromArgb(180, 200, 140),
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 10)
        };

        _radProject.ForeColor = Color.Gainsboro;
        _radJar.ForeColor = Color.Gainsboro;
        _radProject.CheckedChanged += (_, _) => UpdateModeUi();
        _radJar.CheckedChanged += (_, _) => UpdateModeUi();

        var modePanel = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true,
            Dock = DockStyle.Top,
            WrapContents = false
        };
        modePanel.Controls.Add(_radJar);
        modePanel.Controls.Add(_radProject);

        var paths = new TableLayoutPanel
        {
            ColumnCount = 3,
            RowCount = 2,
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 8, 0, 8)
        };
        paths.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110f));
        paths.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        paths.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120f));
        paths.Controls.Add(_lblInput, 0, 0);
        paths.Controls.Add(_txtInput, 1, 0);
        paths.Controls.Add(_btnBrowseIn, 2, 0);
        paths.Controls.Add(new Label { Text = "Output", AutoSize = true, ForeColor = Color.Gainsboro, Margin = new Padding(0, 10, 8, 4) }, 0, 1);
        paths.Controls.Add(_txtOutput, 1, 1);
        paths.Controls.Add(_btnBrowseOut, 2, 1);

        _txtMc.Text = "26.2";
        _txtNeo.Text = "26.2.0.32-beta";
        var opts = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Top, WrapContents = false };
        opts.Controls.Add(_chkContinueNeo);
        opts.Controls.Add(_chkCompile);
        opts.Controls.Add(_chkDry);

        var versions = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, WrapContents = false };
        versions.Controls.Add(new Label { Text = "MC", AutoSize = true, ForeColor = Color.Gainsboro, Margin = new Padding(0, 8, 6, 0) });
        _txtMc.Width = 80;
        versions.Controls.Add(_txtMc);
        versions.Controls.Add(new Label { Text = "Neo", AutoSize = true, ForeColor = Color.Gainsboro, Margin = new Padding(16, 8, 6, 0) });
        _txtNeo.Width = 140;
        versions.Controls.Add(_txtNeo);

        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 8, 0, 8) };
        buttons.Controls.Add(_btnRun);
        buttons.Controls.Add(_btnOpenOut);
        buttons.Controls.Add(_btnClear);

        _log.Dock = DockStyle.Fill;
        _log.BackColor = Color.FromArgb(24, 26, 30);
        _log.ForeColor = Color.Gainsboro;
        _log.Font = new Font("Consolas", 9f);
        _log.ReadOnly = true;
        _log.BorderStyle = BorderStyle.FixedSingle;

        _btnBrowseIn.Click += (_, _) => BrowseInput();
        _btnBrowseOut.Click += (_, _) => BrowseOutput();
        _btnRun.Click += async (_, _) => await RunConvertAsync();
        _btnOpenOut.Click += (_, _) => OpenOutput();
        _btnClear.Click += (_, _) => _log.Clear();

        var top = new Panel { Dock = DockStyle.Top, AutoSize = true };
        top.Controls.Add(buttons);
        top.Controls.Add(versions);
        top.Controls.Add(opts);
        top.Controls.Add(paths);
        top.Controls.Add(modePanel);
        top.Controls.Add(sub);
        top.Controls.Add(header);

        // reverse dock order: last added is topmost visually with Dock.Top stacking
        Controls.Add(_log);
        Controls.Add(new Panel { Height = 28, Dock = DockStyle.Top, Padding = new Padding(0, 4, 0, 4) }.Also(p => p.Controls.Add(_progress)));
        Controls.Add(top);

        // Fix dock stacking - rebuild layout simply
        Controls.Clear();
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 6
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        root.Controls.Add(header, 0, 0);
        root.Controls.Add(sub, 0, 1);
        root.Controls.Add(modePanel, 0, 2);
        root.Controls.Add(paths, 0, 3);
        var mid = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Fill, WrapContents = false };
        mid.Controls.Add(opts);
        mid.Controls.Add(versions);
        mid.Controls.Add(buttons);
        mid.Controls.Add(_progress);
        root.Controls.Add(mid, 0, 4);
        root.Controls.Add(_log, 0, 5);
        Controls.Add(root);

        AppendLog("Ready. Mode B: pick a Forge 1.12.2 jar. This is experimental — not a full auto-port.", Color.LightSkyBlue);
        UpdateModeUi();
    }

    private void UpdateModeUi()
    {
        _lblInput.Text = _radJar.Checked ? "Input .jar" : "Input project";
        _chkContinueNeo.Enabled = _radJar.Checked;
        if (!string.IsNullOrWhiteSpace(_txtInput.Text))
            _txtOutput.Text = SuggestOutput(_txtInput.Text);
    }

    private string SuggestOutput(string input)
    {
        try
        {
            if (_radJar.Checked)
            {
                var full = Path.GetFullPath(input.Trim());
                var name = Path.GetFileNameWithoutExtension(full);
                var parent = Path.GetDirectoryName(full)!;
                var suffix = _chkContinueNeo.Checked && !_chkDry.Checked ? "-26.2" : "-decompiled";
                var candidate = Path.Combine(parent, name + suffix);
                var i = 2;
                while (Directory.Exists(candidate))
                {
                    candidate = Path.Combine(parent, $"{name}{suffix}-{i}");
                    i++;
                }
                return candidate;
            }
            else
            {
                var full = Path.GetFullPath(input.Trim());
                var name = Path.GetFileName(full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
                var parent = Path.GetDirectoryName(full)!;
                var candidate = Path.Combine(parent, name + "-26.2");
                var i = 2;
                while (Directory.Exists(candidate))
                {
                    candidate = Path.Combine(parent, $"{name}-26.2-{i}");
                    i++;
                }
                return candidate;
            }
        }
        catch { return ""; }
    }

    private void BrowseInput()
    {
        if (_radJar.Checked)
        {
            using var dlg = new OpenFileDialog
            {
                Title = "Select Forge 1.12.2 mod .jar",
                Filter = "JAR files (*.jar)|*.jar|All files (*.*)|*.*"
            };
            if (dlg.ShowDialog(this) == DialogResult.OK)
            {
                _txtInput.Text = dlg.FileName;
                _txtOutput.Text = SuggestOutput(dlg.FileName);
            }
        }
        else
        {
            using var dlg = new FolderBrowserDialog { Description = "Select 1.12 project / decompiled folder" };
            if (dlg.ShowDialog(this) == DialogResult.OK)
            {
                _txtInput.Text = dlg.SelectedPath;
                _txtOutput.Text = SuggestOutput(dlg.SelectedPath);
            }
        }
    }

    private void BrowseOutput()
    {
        using var dlg = new FolderBrowserDialog { Description = "Select empty output folder (or parent to create)" };
        if (dlg.ShowDialog(this) == DialogResult.OK)
            _txtOutput.Text = dlg.SelectedPath;
    }

    private void OpenOutput()
    {
        var p = _txtOutput.Text.Trim();
        if (Directory.Exists(p))
            Process.Start(new ProcessStartInfo { FileName = p, UseShellExecute = true });
        else
            MessageBox.Show(this, "Output folder does not exist yet.", "Open output", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private async Task RunConvertAsync()
    {
        if (_busy) return;
        var jarMode = _radJar.Checked;
        var input = _txtInput.Text.Trim();
        var output = _txtOutput.Text.Trim();
        if (string.IsNullOrWhiteSpace(input) || string.IsNullOrWhiteSpace(output))
        {
            MessageBox.Show(this, "Choose input and output paths.", "Convert", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var tools = Path.Combine(AppContext.BaseDirectory, "tools");
        if (!Directory.Exists(tools))
            tools = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));

        string script;
        var args = new List<string> { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File" };
        if (jarMode)
        {
            if (_chkContinueNeo.Checked && !_chkDry.Checked)
            {
                script = Path.Combine(tools, "Convert-OldJar112ToNeoForge262.ps1");
                args.Add(Quote(script));
                args.AddRange(new[] { "-JarPath", Quote(input), "-OutputPath", Quote(output) });
            }
            else
            {
                script = Path.Combine(tools, "Convert-JarToProject112.ps1");
                args.Add(Quote(script));
                args.AddRange(new[] { "-JarPath", Quote(input), "-OutputPath", Quote(output) });
            }
        }
        else
        {
            script = Path.Combine(tools, "Convert-112ToNeoForge262.ps1");
            args.Add(Quote(script));
            args.AddRange(new[] { "-Path", Quote(input), "-OutputPath", Quote(output) });
        }

        if (!File.Exists(script))
        {
            MessageBox.Show(this, "Tool script missing:\n" + script, "Convert", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        args.AddRange(new[] { "-MinecraftVersion", Quote(_txtMc.Text.Trim()), "-NeoVersion", Quote(_txtNeo.Text.Trim()) });
        if (_chkCompile.Checked) args.Add("-Compile");
        if (_chkDry.Checked) args.Add("-DryRun");

        _busy = true;
        _btnRun.Enabled = false;
        _progress.Visible = true;
        AppendLog("Starting: " + script, Color.LightSkyBlue);
        AppendLog("Args: " + string.Join(" ", args.Skip(4)), Color.Gray);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = string.Join(" ", args),
                WorkingDirectory = Path.GetDirectoryName(script)!,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };
            _running = new Process { StartInfo = psi, EnableRaisingEvents = true };
            _running.OutputDataReceived += (_, e) => { if (e.Data != null) BeginInvoke(() => AppendLog(e.Data, Color.Gainsboro)); };
            _running.ErrorDataReceived += (_, e) => { if (e.Data != null) BeginInvoke(() => AppendLog(e.Data, Color.Salmon)); };
            _running.Start();
            _running.BeginOutputReadLine();
            _running.BeginErrorReadLine();
            await _running.WaitForExitAsync();
            var code = _running.ExitCode;
            AppendLog(code == 0 ? "Finished OK (exit 0)." : $"Finished with exit {code}.", code == 0 ? Color.LightGreen : Color.Orange);
            if (code == 0 && Directory.Exists(output))
                AppendLog("Open output and read MIGRATION_112_REPORT.md / DECOMPILE_REPORT.md", Color.Khaki);
        }
        catch (Exception ex)
        {
            AppendLog("ERROR: " + ex.Message, Color.OrangeRed);
        }
        finally
        {
            _running = null;
            _busy = false;
            _btnRun.Enabled = true;
            _progress.Visible = false;
        }
    }

    private void AppendLog(string text, Color color)
    {
        _log.SelectionStart = _log.TextLength;
        _log.SelectionLength = 0;
        _log.SelectionColor = color;
        _log.AppendText(text + Environment.NewLine);
        _log.ScrollToCaret();
    }

    private static string Quote(string s) => "\"" + s.Replace("\"", "\\\"") + "\"";

    private static TextBox NewTextBox() => new()
    {
        Dock = DockStyle.Fill,
        BackColor = Color.FromArgb(45, 48, 55),
        ForeColor = Color.White,
        BorderStyle = BorderStyle.FixedSingle,
        Margin = new Padding(0, 4, 8, 4)
    };

    private static CheckBox NewCheck(string text, bool on) => new()
    {
        Text = text,
        AutoSize = true,
        Checked = on,
        ForeColor = Color.Gainsboro,
        Margin = new Padding(0, 4, 0, 2)
    };

    private static Button NewButton(string text, int w) => new()
    {
        Text = text,
        Width = w,
        Height = 32,
        FlatStyle = FlatStyle.Flat,
        BackColor = Color.FromArgb(60, 90, 140),
        ForeColor = Color.White,
        Margin = new Padding(0, 4, 8, 4)
    };
}

internal static class ControlExt
{
    public static T Also<T>(this T c, Action<T> a) { a(c); return c; }
}
