using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Application = System.Windows.Application;
using WpfButton = System.Windows.Controls.Button;
using Forms = System.Windows.Forms;

namespace Devar.Windows;

public sealed record AudioDevice(int Id, string Name);
public sealed record VerseSuggestion(string Reference, string Translation, string Text);

public partial class MainWindow : Window
{
    private readonly SpeechBridge _bridge = new();
    private readonly Forms.NotifyIcon _trayIcon;
    private readonly ObservableCollection<VerseSuggestion> _alternatives = [];
    private readonly string _settingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Devar", "settings.json");
    private string? _bibleDirectory;
    private VerseSuggestion? _currentSuggestion;
    private bool _isListening;
    private bool _quitting;

    public MainWindow()
    {
        InitializeComponent();
        AlternativesList.ItemsSource = _alternatives;
        LoadSettings();
        var iconPath = Path.Combine(AppContext.BaseDirectory, "devar.ico");
        var icon = File.Exists(iconPath) ? new System.Drawing.Icon(iconPath) : Forms.SystemIcons.Application;
        _trayIcon = new Forms.NotifyIcon { Icon = icon, Text = "Devar scripture suggestions", Visible = true };
        _trayIcon.DoubleClick += (_, _) => Dispatcher.Invoke(ToggleWindow);
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open Devar", null, (_, _) => Dispatcher.Invoke(ShowPanel));
        menu.Items.Add("Start listening", null, (_, _) => Dispatcher.Invoke(() => Start_Click(this, new RoutedEventArgs())));
        menu.Items.Add("Stop listening", null, (_, _) => Dispatcher.Invoke(() => Stop_Click(this, new RoutedEventArgs())));
        menu.Items.Add("Quit", null, (_, _) => Dispatcher.Invoke(() => Quit_Click(this, new RoutedEventArgs())));
        _trayIcon.ContextMenuStrip = menu;
        _bridge.EventReceived += OnBridgeEvent;
        try { _bridge.Start(_bibleDirectory); }
        catch (Exception ex) { StatusText.Text = "Needs setup"; SetNotice(ex.Message); }
        if (Forms.Screen.PrimaryScreen is { } screen)
        {
            Left = Math.Max(screen.WorkingArea.Left, screen.WorkingArea.Right - Width - 20);
            Top = Math.Max(screen.WorkingArea.Top, screen.WorkingArea.Bottom - Height - 20);
        }
        if (!string.IsNullOrWhiteSpace(_bibleDirectory))
            _bridge.Send(new { action = "prepare", translation = SelectedTranslation });
        else
            SetNotice("Choose your licensed Bible data folder to finish setup.");
        Closing += (_, e) => { if (!_quitting) { e.Cancel = true; Hide(); } };
    }

    private string SelectedTranslation => (TranslationPicker.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "NKJV";

    private void LoadSettings()
    {
        try
        {
            if (!File.Exists(_settingsPath)) return;
            using var data = JsonDocument.Parse(File.ReadAllText(_settingsPath));
            if (data.RootElement.TryGetProperty("bibleDirectory", out var path)) _bibleDirectory = path.GetString();
            if (data.RootElement.TryGetProperty("translation", out var translation))
            {
                var value = translation.GetString();
                foreach (ComboBoxItem item in TranslationPicker.Items)
                    if (item.Content?.ToString() == value) TranslationPicker.SelectedItem = item;
            }
        }
        catch { _bibleDirectory = null; }
    }

    private void SaveSettings()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);
            File.WriteAllText(_settingsPath, JsonSerializer.Serialize(new { bibleDirectory = _bibleDirectory, translation = SelectedTranslation }));
        }
        catch (Exception ex) { SetNotice($"Could not save settings: {ex.Message}"); }
    }

    private void OnBridgeEvent(JsonElement message)
    {
        Dispatcher.Invoke(() =>
        {
            var type = GetString(message, "type");
            switch (type)
            {
                case "ready":
                case "devices":
                    if (message.TryGetProperty("devices", out var devices))
                    {
                        var previous = (DevicePicker.SelectedItem as AudioDevice)?.Id;
                        var list = devices.EnumerateArray().Select(item => new AudioDevice(
                            item.GetProperty("id").GetInt32(), item.GetProperty("name").GetString() ?? "Audio input")).ToList();
                        DevicePicker.ItemsSource = list;
                        DevicePicker.SelectedItem = list.FirstOrDefault(item => item.Id == previous) ?? list.FirstOrDefault();
                    }
                    if (GetString(message, "engine") is { } engine) EngineText.Text = engine + " · local scripture search";
                    break;
                case "state":
                    var state = GetString(message, "state");
                    _isListening = state == "listening";
                    StatusText.Text = state switch
                    {
                        "listening" => "● Listening · " + (DevicePicker.SelectedItem as AudioDevice)?.Name,
                        "loading-data" => "Loading scripture data…",
                        "loading-model" => "Preparing speech model…",
                        "connecting" => "Connecting to audio input…",
                        "prepared" => "Ready · " + (DevicePicker.SelectedItem as AudioDevice)?.Name,
                        "paused" => "Paused",
                        "error" => "Needs attention",
                        _ => "Stopped · " + (DevicePicker.SelectedItem as AudioDevice)?.Name
                    };
                    StartButton.IsEnabled = !_isListening && state is not ("loading-data" or "loading-model" or "connecting");
                    StopButton.IsEnabled = _isListening || state == "connecting";
                    if (state == "prepared") SetNotice("Ready when you are");
                    break;
                case "notice": SetNotice(GetString(message, "message") ?? "Local speech service notice"); break;
                case "error": SetNotice(GetString(message, "message") ?? "The local speech service reported an error."); break;
                case "transcript": TranscriptText.Text = GetString(message, "text") is { Length: > 0 } text ? text : "Your live transcript will appear here."; break;
                case "suggestions":
                    List<VerseSuggestion> verses = message.TryGetProperty("suggestions", out var values)
                        ? values.EnumerateArray().Select(value => new VerseSuggestion(
                            GetString(value, "reference") ?? "", GetString(value, "translation") ?? SelectedTranslation,
                            GetString(value, "text") ?? "")).Where(value => value.Reference.Length > 0).ToList()
                        : [];
                    _currentSuggestion = verses.FirstOrDefault();
                    ReferenceText.Text = _currentSuggestion?.Reference ?? "No passage yet";
                    VerseText.Text = _currentSuggestion?.Text ?? "Scripture matches will appear here.";
                    CopyReferenceButton.IsEnabled = CopyVerseButton.IsEnabled = _currentSuggestion is not null;
                    _alternatives.Clear();
                    foreach (var verse in verses.Skip(1)) _alternatives.Add(verse);
                    break;
            }
        });
    }

    private static string? GetString(JsonElement element, string key) =>
        element.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private void SetNotice(string value) => NoticeText.Text = value;

    private void Start_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_bibleDirectory))
        {
            ChooseBible_Click(sender, e);
            if (string.IsNullOrWhiteSpace(_bibleDirectory)) return;
            _bridge.Send(new { action = "set-bible-directory", path = _bibleDirectory, translation = SelectedTranslation });
            return;
        }
        if (DevicePicker.SelectedItem is not AudioDevice device) { SetNotice("Choose an audio input before starting."); return; }
        SaveSettings();
        _bridge.Send(new { action = "start", deviceId = device.Id, translation = SelectedTranslation,
            suggestionCount = 3, refreshSeconds = 1, contextSeconds = 30 });
    }

    private void Stop_Click(object sender, RoutedEventArgs e) => _bridge.Send(new { action = "stop" });
    private void Refresh_Click(object sender, RoutedEventArgs e) => _bridge.Send(new { action = "refresh-devices" });

    private void ChooseBible_Click(object sender, RoutedEventArgs e)
    {
        using var dialog = new Forms.FolderBrowserDialog { Description = "Choose a folder with licensed Bible JSON files, such as nkjv.json." };
        if (dialog.ShowDialog() != Forms.DialogResult.OK) return;
        _bibleDirectory = dialog.SelectedPath;
        SaveSettings();
        SetNotice("Loading Bible data and preparing local speech model…");
        _bridge.Send(new { action = "set-bible-directory", path = _bibleDirectory, translation = SelectedTranslation });
    }

    private void CopyReference_Click(object sender, RoutedEventArgs e)
    {
        if (_currentSuggestion is not null) System.Windows.Clipboard.SetText(_currentSuggestion.Reference);
    }
    private void CopyVerse_Click(object sender, RoutedEventArgs e)
    {
        if (_currentSuggestion is not null) System.Windows.Clipboard.SetText(_currentSuggestion.Text);
    }
    private void Alternative_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as WpfButton)?.Tag is not VerseSuggestion verse) return;
        _alternatives.Remove(verse);
        if (_currentSuggestion is not null) _alternatives.Insert(0, _currentSuggestion);
        _currentSuggestion = verse;
        ReferenceText.Text = verse.Reference;
        VerseText.Text = verse.Text;
        CopyReferenceButton.IsEnabled = CopyVerseButton.IsEnabled = true;
    }

    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); }
    private void Minimize_Click(object sender, RoutedEventArgs e) => Hide();
    private void ToggleWindow() { if (IsVisible) Hide(); else ShowPanel(); }
    private void ShowPanel() { Show(); WindowState = WindowState.Normal; Activate(); }
    private void Quit_Click(object sender, RoutedEventArgs e)
    {
        _quitting = true;
        _bridge.Send(new { action = "quit" });
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _bridge.Dispose();
        Application.Current.Shutdown();
    }
}

internal sealed class SpeechBridge : IDisposable
{
    private readonly object _writeLock = new();
    private Process? _process;
    public event Action<JsonElement>? EventReceived;

    public void Start(string? bibleDirectory)
    {
        var baseDirectory = AppContext.BaseDirectory;
        var packaged = Path.Combine(baseDirectory, "Speech", "desktop_bridge.exe");
        var helper = FindHelper();
        ProcessStartInfo start;
        if (File.Exists(packaged)) start = new ProcessStartInfo(packaged) { WorkingDirectory = baseDirectory, UseShellExecute = false, CreateNoWindow = true };
        else if (helper is not null)
        {
            var python = Path.Combine(FindRepositoryRoot() ?? "", ".venv", "Scripts", "python.exe");
            start = new ProcessStartInfo(File.Exists(python) ? python : "python") { WorkingDirectory = FindRepositoryRoot() ?? Environment.CurrentDirectory, UseShellExecute = false, CreateNoWindow = true };
            start.ArgumentList.Add(helper);
        }
        else throw new FileNotFoundException("The Devar speech service is missing. Build it with windows/build.ps1 or follow the Windows development steps in the README.");
        start.RedirectStandardInput = true;
        start.RedirectStandardOutput = true;
        start.RedirectStandardError = true;
        if (!string.IsNullOrWhiteSpace(bibleDirectory)) start.Environment["DEVAR_BIBLE_DIR"] = bibleDirectory;
        _process = Process.Start(start) ?? throw new InvalidOperationException("Could not start the local speech service.");
        _ = Task.Run(async () =>
        {
            while (await _process.StandardOutput.ReadLineAsync() is { } line)
            {
                try { using var doc = JsonDocument.Parse(line); EventReceived?.Invoke(doc.RootElement.Clone()); }
                catch (JsonException) { }
            }
        });
        _ = Task.Run(async () =>
        {
            while (await _process.StandardError.ReadLineAsync() is { } line)
                System.Diagnostics.Debug.WriteLine("Devar speech: " + line);
        });
    }

    private static string? FindHelper()
    {
        var root = FindRepositoryRoot();
        if (root is not null)
        {
            var direct = Path.Combine(root, "Sources", "DevarDesktop", "Resources", "desktop_bridge.py");
            if (File.Exists(direct)) return direct;
            var nested = Path.Combine(root, "apps", "desktop", "Sources", "DevarDesktop", "Resources", "desktop_bridge.py");
            if (File.Exists(nested)) return nested;
        }
        var candidate = new DirectoryInfo(Environment.CurrentDirectory);
        while (candidate is not null)
        {
            var file = Path.Combine(candidate.FullName, "apps", "desktop", "Sources", "DevarDesktop", "Resources", "desktop_bridge.py");
            if (File.Exists(file)) return file;
            candidate = candidate.Parent;
        }
        return null;
    }
    private static string? FindRepositoryRoot()
    {
        var candidate = new DirectoryInfo(Environment.CurrentDirectory);
        while (candidate is not null)
        {
            if (File.Exists(Path.Combine(candidate.FullName, "Package.swift")) &&
                Directory.Exists(Path.Combine(candidate.FullName, "Sources", "DevarDesktop"))) return candidate.FullName;
            if (File.Exists(Path.Combine(candidate.FullName, "apps", "desktop", "Package.swift"))) return candidate.FullName;
            candidate = candidate.Parent;
        }
        return null;
    }

    public void Send(object command)
    {
        lock (_writeLock)
        {
            if (_process is null || _process.HasExited) return;
            _process.StandardInput.WriteLine(JsonSerializer.Serialize(command));
            _process.StandardInput.Flush();
        }
    }
    public void Dispose()
    {
        try { if (_process is { HasExited: false }) { Send(new { action = "quit" }); _process.WaitForExit(3000); if (!_process.HasExited) _process.Kill(true); } }
        catch { }
        _process?.Dispose();
    }
}
