using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("Codex 额度小组件")]
[assembly: AssemblyDescription("在 Windows 任务栏旁实时显示 Codex 5 小时与周额度")]
[assembly: AssemblyCompany("Local utility")]
[assembly: AssemblyProduct("Codex Quota Widget")]
[assembly: AssemblyCopyright("Copyright 2026")]
[assembly: ComVisible(false)]
[assembly: Guid("E7979E76-F3B7-45B5-A4D9-A5385F8E0B57")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

namespace CodexQuotaWidget
{
    internal static class Program
    {
        private const string MutexName = "Local\\CodexQuotaWidget_6F8E4D53";

        [STAThread]
        private static void Main(string[] args)
        {
            bool createdNew;
            using (var mutex = new Mutex(true, MutexName, out createdNew))
            {
                if (!createdNew)
                {
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new QuotaWidgetForm());
            }
        }
    }
}

namespace CodexQuotaWidget
{
    internal sealed class QuotaWindow
    {
        public double UsedPercent { get; set; }
        public int WindowDurationMinutes { get; set; }
        public DateTime? ResetsAtLocal { get; set; }

        public int RemainingPercent
        {
            get
            {
                var remaining = (int)Math.Round(100.0 - UsedPercent, MidpointRounding.AwayFromZero);
                return Math.Max(0, Math.Min(100, remaining));
            }
        }
    }

    internal sealed class QuotaSnapshot
    {
        public QuotaWindow FiveHour { get; set; }
        public QuotaWindow Weekly { get; set; }
        public DateTime UpdatedAtLocal { get; set; }
        public string Error { get; set; }

        public static QuotaSnapshot Loading()
        {
            return new QuotaSnapshot
            {
                UpdatedAtLocal = DateTime.Now,
                Error = "正在连接 Codex…"
            };
        }
    }
}

namespace CodexQuotaWidget
{
    internal static class NativeMethods
    {
        internal const int GWL_EXSTYLE = -20;
        internal const int WS_EX_TOOLWINDOW = 0x00000080;
        internal const int WS_EX_NOACTIVATE = 0x08000000;
        internal const int SWP_NOACTIVATE = 0x0010;
        internal const int SWP_SHOWWINDOW = 0x0040;
        internal static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)]
        internal struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;

            public int Width { get { return Right - Left; } }
            public int Height { get { return Bottom - Top; } }
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        internal static extern IntPtr FindWindow(string className, string windowName);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        internal static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string windowName);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetWindowRect(IntPtr window, out RECT rect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

        [DllImport("user32.dll")]
        internal static extern int GetWindowLong(IntPtr window, int index);

        [DllImport("user32.dll")]
        internal static extern int SetWindowLong(IntPtr window, int index, int value);
    }
}

namespace CodexQuotaWidget
{
    internal sealed class WidgetSettings
    {
        private static readonly string DirectoryPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CodexQuotaWidget");
        private static readonly string FilePath = Path.Combine(DirectoryPath, "settings.json");

        public int HorizontalOffset { get; set; }
        public string Language { get; set; }
        public int LayoutVersion { get; set; }

        public static WidgetSettings Load()
        {
            try
            {
                if (!File.Exists(FilePath))
                {
                    return new WidgetSettings { Language = "zh-CN", LayoutVersion = 2 };
                }
                var json = new JavaScriptSerializer();
                var values = json.DeserializeObject(File.ReadAllText(FilePath)) as Dictionary<string, object>;
                object value;
                object layoutValue;
                var layoutVersion = values != null && values.TryGetValue("layoutVersion", out layoutValue)
                    ? Convert.ToInt32(layoutValue, CultureInfo.InvariantCulture)
                    : 0;
                return new WidgetSettings
                {
                    HorizontalOffset = layoutVersion >= 2 && values != null && values.TryGetValue("horizontalOffset", out value)
                        ? Convert.ToInt32(value, CultureInfo.InvariantCulture)
                        : 0,
                    Language = values != null && values.TryGetValue("language", out value)
                        ? Convert.ToString(value, CultureInfo.InvariantCulture)
                        : "zh-CN",
                    LayoutVersion = 2
                };
            }
            catch
            {
                return new WidgetSettings { Language = "zh-CN", LayoutVersion = 2 };
            }
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(DirectoryPath);
                var json = new JavaScriptSerializer();
                var values = new Dictionary<string, object>
                {
                    { "horizontalOffset", HorizontalOffset },
                    { "language", string.IsNullOrWhiteSpace(Language) ? "zh-CN" : Language },
                    { "layoutVersion", 2 }
                };
                File.WriteAllText(FilePath, json.Serialize(values));
            }
            catch
            {
            }
        }
    }
}

namespace CodexQuotaWidget
{
    internal sealed class CodexRateLimitClient : IDisposable
    {
        private readonly object sync = new object();
        private readonly JavaScriptSerializer json = new JavaScriptSerializer();
        private Process process;
        private StreamWriter input;
        private System.Threading.Timer refreshTimer;
        private System.Threading.Timer reconnectTimer;
        private bool initialized;
        private bool disposed;
        private int nextRequestId = 10;

        public event Action<QuotaSnapshot> SnapshotChanged;

        public void Start()
        {
            ThreadPool.QueueUserWorkItem(delegate { Connect(); });
        }

        public void Refresh()
        {
            lock (sync)
            {
                if (!initialized || input == null)
                {
                    ScheduleReconnect(1000);
                    return;
                }

                SendLocked("{\"method\":\"account/rateLimits/read\",\"id\":" + nextRequestId.ToString(CultureInfo.InvariantCulture) + "}");
                nextRequestId++;
            }
        }

        private void Connect()
        {
            if (disposed)
            {
                return;
            }

            try
            {
                var launch = ResolveCodexLaunch();
                var start = new ProcessStartInfo
                {
                    FileName = launch.Item1,
                    Arguments = launch.Item2,
                    WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    StandardOutputEncoding = System.Text.Encoding.UTF8,
                    StandardErrorEncoding = System.Text.Encoding.UTF8
                };

                var child = new Process { StartInfo = start, EnableRaisingEvents = true };
                child.OutputDataReceived += OnOutput;
                child.ErrorDataReceived += OnError;
                child.Exited += OnExited;
                child.Start();
                child.BeginOutputReadLine();
                child.BeginErrorReadLine();

                lock (sync)
                {
                    if (disposed)
                    {
                        TryStop(child);
                        return;
                    }

                    process = child;
                    input = child.StandardInput;
                    input.AutoFlush = true;
                    initialized = false;
                    SendLocked("{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"codex_quota_widget\",\"title\":\"Codex Quota Widget\",\"version\":\"1.1.0\"}}}");
                }
            }
            catch (Exception ex)
            {
                PublishError(FriendlyError(ex));
                ScheduleReconnect(15000);
            }
        }

        private void OnOutput(object sender, DataReceivedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(e.Data))
            {
                return;
            }

            try
            {
                var message = json.DeserializeObject(e.Data) as Dictionary<string, object>;
                if (message == null)
                {
                    return;
                }

                object idObject;
                if (message.TryGetValue("id", out idObject) && Convert.ToInt32(idObject, CultureInfo.InvariantCulture) == 1)
                {
                    lock (sync)
                    {
                        if (input == null)
                        {
                            return;
                        }

                        SendLocked("{\"method\":\"initialized\"}");
                        initialized = true;
                        SendLocked("{\"method\":\"account/rateLimits/read\",\"id\":2}");
                        StartRefreshTimerLocked();
                    }
                    return;
                }

                Dictionary<string, object> rateLimits = null;
                object resultObject;
                if (message.TryGetValue("result", out resultObject))
                {
                    rateLimits = ExtractRateLimits(resultObject as Dictionary<string, object>);
                }

                object methodObject;
                if (rateLimits == null && message.TryGetValue("method", out methodObject) &&
                    string.Equals(Convert.ToString(methodObject, CultureInfo.InvariantCulture), "account/rateLimits/updated", StringComparison.Ordinal))
                {
                    object paramsObject;
                    if (message.TryGetValue("params", out paramsObject))
                    {
                        rateLimits = ExtractRateLimits(paramsObject as Dictionary<string, object>);
                    }
                }

                if (rateLimits != null)
                {
                    Publish(ParseSnapshot(rateLimits));
                    return;
                }

                object errorObject;
                if (message.TryGetValue("error", out errorObject))
                {
                    var error = errorObject as Dictionary<string, object>;
                    object errorMessage;
                    PublishError(error != null && error.TryGetValue("message", out errorMessage)
                        ? Convert.ToString(errorMessage, CultureInfo.InvariantCulture)
                        : "Codex 返回了错误");
                }
            }
            catch (Exception ex)
            {
                PublishError("额度数据格式无法识别：" + ex.Message);
            }
        }

        private static Dictionary<string, object> ExtractRateLimits(Dictionary<string, object> envelope)
        {
            if (envelope == null)
            {
                return null;
            }

            Dictionary<string, object> selected = null;
            object limitsObject;
            if (envelope.TryGetValue("rateLimits", out limitsObject))
            {
                selected = limitsObject as Dictionary<string, object>;
            }

            object groupsObject;
            var groups = envelope.TryGetValue("rateLimitsByLimitId", out groupsObject)
                ? groupsObject as Dictionary<string, object>
                : null;
            if (groups != null)
            {
                foreach (var entry in groups)
                {
                    var candidate = entry.Value as Dictionary<string, object>;
                    if (candidate != null && ScoreRateLimits(candidate) > ScoreRateLimits(selected))
                    {
                        selected = candidate;
                    }
                }
            }

            if (selected != null)
            {
                return selected;
            }

            if (envelope.ContainsKey("primary") || envelope.ContainsKey("secondary"))
            {
                return envelope;
            }

            return null;
        }

        private static int ScoreRateLimits(Dictionary<string, object> limits)
        {
            if (limits == null)
            {
                return -1;
            }

            var score = 0;
            foreach (var key in new[] { "primary", "secondary" })
            {
                object windowObject;
                var window = limits.TryGetValue(key, out windowObject) ? windowObject as Dictionary<string, object> : null;
                object durationObject;
                if (window == null || !window.TryGetValue("windowDurationMins", out durationObject) || durationObject == null)
                {
                    continue;
                }

                var minutes = Convert.ToInt32(durationObject, CultureInfo.InvariantCulture);
                score += minutes == 300 || minutes == 10080 ? 2 : 1;
            }
            return score;
        }

        internal static QuotaSnapshot ParseSnapshot(Dictionary<string, object> limits)
        {
            var snapshot = new QuotaSnapshot { UpdatedAtLocal = DateTime.Now };
            var windows = new List<QuotaWindow>();

            AddWindow(limits, "primary", windows);
            AddWindow(limits, "secondary", windows);

            snapshot.FiveHour = windows.FirstOrDefault(delegate(QuotaWindow item) { return item.WindowDurationMinutes == 300; });
            snapshot.Weekly = windows.FirstOrDefault(delegate(QuotaWindow item) { return item.WindowDurationMinutes == 10080; });

            var unknown = windows.Where(delegate(QuotaWindow item)
            {
                return item.WindowDurationMinutes != 300 && item.WindowDurationMinutes != 10080;
            }).ToList();

            if (snapshot.FiveHour == null && unknown.Count > 0)
            {
                snapshot.FiveHour = unknown[0];
            }
            if (snapshot.Weekly == null && unknown.Count > 1)
            {
                snapshot.Weekly = unknown[1];
            }

            if (snapshot.FiveHour == null && snapshot.Weekly == null)
            {
                snapshot.Error = "当前账号没有返回额度窗口";
            }

            return snapshot;
        }

        private static void AddWindow(Dictionary<string, object> limits, string key, IList<QuotaWindow> windows)
        {
            object windowObject;
            if (!limits.TryGetValue(key, out windowObject) || windowObject == null)
            {
                return;
            }

            var values = windowObject as Dictionary<string, object>;
            if (values == null)
            {
                return;
            }

            var window = new QuotaWindow();
            object value;
            if (values.TryGetValue("usedPercent", out value))
            {
                window.UsedPercent = Convert.ToDouble(value, CultureInfo.InvariantCulture);
            }
            if (values.TryGetValue("windowDurationMins", out value))
            {
                window.WindowDurationMinutes = Convert.ToInt32(value, CultureInfo.InvariantCulture);
            }
            if (values.TryGetValue("resetsAt", out value) && value != null)
            {
                var unixSeconds = Convert.ToInt64(value, CultureInfo.InvariantCulture);
                window.ResetsAtLocal = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(unixSeconds).ToLocalTime();
            }
            windows.Add(window);
        }

        private static Tuple<string, string> ResolveCodexLaunch()
        {
            var overridePath = Environment.GetEnvironmentVariable("CODEX_EXE");
            if (!string.IsNullOrWhiteSpace(overridePath) && File.Exists(overridePath))
            {
                return Tuple.Create(overridePath, "app-server");
            }

            // Codex Desktop keeps a directly executable copy here. Prefer it over
            // the WindowsApps package path, whose ACL can reject child launches.
            var desktopCopy = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".codex", ".sandbox-bin", "codex.exe");
            if (File.Exists(desktopCopy))
            {
                return Tuple.Create(desktopCopy, "app-server");
            }

            try
            {
                foreach (var candidate in Process.GetProcessesByName("codex"))
                {
                    try
                    {
                        var fileName = candidate.MainModule.FileName;
                        if (File.Exists(fileName))
                        {
                            return Tuple.Create(fileName, "app-server");
                        }
                    }
                    catch
                    {
                    }
                    finally
                    {
                        candidate.Dispose();
                    }
                }
            }
            catch
            {
            }

            var localAlias = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "WindowsApps", "codex.exe");
            if (File.Exists(localAlias))
            {
                return Tuple.Create(localAlias, "app-server");
            }

            var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
            foreach (var directory in path.Split(Path.PathSeparator))
            {
                try
                {
                    var exe = Path.Combine(directory.Trim(), "codex.exe");
                    if (File.Exists(exe))
                    {
                        return Tuple.Create(exe, "app-server");
                    }

                    var cmd = Path.Combine(directory.Trim(), "codex.cmd");
                    if (File.Exists(cmd))
                    {
                        return Tuple.Create(Environment.GetEnvironmentVariable("COMSPEC") ?? "cmd.exe", "/d /s /c \"\"" + cmd + "\" app-server\"");
                    }
                }
                catch
                {
                }
            }

            throw new FileNotFoundException("未找到 codex.exe。请先安装并登录 Codex，或设置 CODEX_EXE 环境变量。");
        }

        private void OnError(object sender, DataReceivedEventArgs e)
        {
            if (!string.IsNullOrWhiteSpace(e.Data) && e.Data.IndexOf("error", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                Debug.WriteLine(e.Data);
            }
        }

        private void OnExited(object sender, EventArgs e)
        {
            if (disposed)
            {
                return;
            }

            lock (sync)
            {
                initialized = false;
                input = null;
                process = null;
                if (refreshTimer != null)
                {
                    refreshTimer.Dispose();
                    refreshTimer = null;
                }
            }

            PublishError("Codex 连接已断开，正在重试…");
            ScheduleReconnect(15000);
        }

        private void StartRefreshTimerLocked()
        {
            if (refreshTimer != null)
            {
                refreshTimer.Dispose();
            }
            refreshTimer = new System.Threading.Timer(delegate { Refresh(); }, null, TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(1));
        }

        private void ScheduleReconnect(int delayMilliseconds)
        {
            lock (sync)
            {
                if (disposed)
                {
                    return;
                }
                if (reconnectTimer != null)
                {
                    reconnectTimer.Dispose();
                }
                reconnectTimer = new System.Threading.Timer(delegate
                {
                    lock (sync)
                    {
                        if (reconnectTimer != null)
                        {
                            reconnectTimer.Dispose();
                            reconnectTimer = null;
                        }
                    }
                    Connect();
                }, null, delayMilliseconds, Timeout.Infinite);
            }
        }

        private void SendLocked(string line)
        {
            input.WriteLine(line);
        }

        private void Publish(QuotaSnapshot snapshot)
        {
            var handler = SnapshotChanged;
            if (handler != null)
            {
                handler(snapshot);
            }
        }

        private void PublishError(string message)
        {
            Publish(new QuotaSnapshot { UpdatedAtLocal = DateTime.Now, Error = message });
        }

        private static string FriendlyError(Exception ex)
        {
            if (ex is FileNotFoundException)
            {
                return ex.Message;
            }
            return "无法连接 Codex：" + ex.Message;
        }

        private static void TryStop(Process child)
        {
            try
            {
                if (!child.HasExited)
                {
                    child.Kill();
                }
            }
            catch
            {
            }
            child.Dispose();
        }

        public void Dispose()
        {
            lock (sync)
            {
                disposed = true;
                if (refreshTimer != null)
                {
                    refreshTimer.Dispose();
                    refreshTimer = null;
                }
                if (reconnectTimer != null)
                {
                    reconnectTimer.Dispose();
                    reconnectTimer = null;
                }
                if (input != null)
                {
                    try { input.Close(); } catch { }
                    input = null;
                }
                if (process != null)
                {
                    TryStop(process);
                    process = null;
                }
            }
        }
    }
}

namespace CodexQuotaWidget
{
    internal sealed class QuotaWidgetForm : Form
    {
        private readonly CodexRateLimitClient client;
        private readonly WidgetSettings settings;
        private readonly System.Windows.Forms.Timer positionTimer;
        private readonly ToolTip toolTip;
        private ContextMenuStrip menu;
        private QuotaSnapshot snapshot;
        private NativeMethods.RECT lastTaskbar;
        private NativeMethods.RECT lastTray;
        private bool dragging;
        private Point dragStartMouse;
        private int dragStartOffset;

        public QuotaWidgetForm()
        {
            settings = WidgetSettings.Load();
            snapshot = QuotaSnapshot.Loading();

            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = Color.FromArgb(30, 30, 30);
            DoubleBuffered = true;
            Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular, GraphicsUnit.Point);

            menu = BuildMenu();
            ContextMenuStrip = menu;
            toolTip = new ToolTip
            {
                InitialDelay = 250,
                ReshowDelay = 100,
                AutoPopDelay = 15000,
                ShowAlways = true
            };

            MouseDown += OnWidgetMouseDown;
            MouseMove += OnWidgetMouseMove;
            MouseUp += OnWidgetMouseUp;
            MouseDoubleClick += delegate { client.Refresh(); };

            positionTimer = new System.Windows.Forms.Timer { Interval = 1000 };
            positionTimer.Tick += delegate { PositionOverTaskbar(false); };

            client = new CodexRateLimitClient();
            client.SnapshotChanged += OnSnapshotChanged;

            Shown += delegate
            {
                ApplyExtendedStyles();
                PositionOverTaskbar(true);
                positionTimer.Start();
                client.Start();
                UpdateToolTip();
            };
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                var parameters = base.CreateParams;
                parameters.ExStyle |= NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE;
                return parameters;
            }
        }

        private ContextMenuStrip BuildMenu()
        {
            var chinese = IsChinese;
            var result = new ContextMenuStrip
            {
                Font = new Font("Microsoft YaHei UI", 9f),
                ShowImageMargin = false
            };

            var refresh = new ToolStripMenuItem(chinese ? "立即刷新" : "Refresh now");
            refresh.Click += delegate { client.Refresh(); };
            result.Items.Add(refresh);

            var reset = new ToolStripMenuItem(chinese ? "固定到天气旁边" : "Pin beside weather");
            reset.Click += delegate
            {
                settings.HorizontalOffset = 0;
                settings.Save();
                PositionOverTaskbar(true);
            };
            result.Items.Add(reset);

            var language = new ToolStripMenuItem(chinese ? "语言" : "Language");
            var chineseItem = new ToolStripMenuItem("中文") { Checked = chinese };
            chineseItem.Click += delegate { SwitchLanguage("zh-CN"); };
            var englishItem = new ToolStripMenuItem("English") { Checked = !chinese };
            englishItem.Click += delegate { SwitchLanguage("en-US"); };
            language.DropDownItems.Add(chineseItem);
            language.DropDownItems.Add(englishItem);
            result.Items.Add(language);
            result.Items.Add(new ToolStripSeparator());

            var startupHint = new ToolStripMenuItem(chinese ? "提示：拖动可微调位置" : "Tip: drag to fine-tune position") { Enabled = false };
            result.Items.Add(startupHint);
            result.Items.Add(new ToolStripSeparator());

            var exit = new ToolStripMenuItem(chinese ? "退出" : "Exit");
            exit.Click += delegate { Close(); };
            result.Items.Add(exit);
            return result;
        }

        private bool IsChinese
        {
            get { return !string.Equals(settings.Language, "en-US", StringComparison.OrdinalIgnoreCase); }
        }

        private void SwitchLanguage(string language)
        {
            settings.Language = language;
            settings.Save();

            var oldMenu = menu;
            menu = BuildMenu();
            ContextMenuStrip = menu;
            if (oldMenu != null)
            {
                oldMenu.Dispose();
            }

            UpdateToolTip();
            Invalidate();
        }

        private void ApplyExtendedStyles()
        {
            var styles = NativeMethods.GetWindowLong(Handle, NativeMethods.GWL_EXSTYLE);
            NativeMethods.SetWindowLong(Handle, NativeMethods.GWL_EXSTYLE,
                styles | NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE);
        }

        private void PositionOverTaskbar(bool force)
        {
            if (dragging)
            {
                return;
            }

            var taskbar = NativeMethods.FindWindow("Shell_TrayWnd", null);
            NativeMethods.RECT taskbarRect;
            if (taskbar == IntPtr.Zero || !NativeMethods.GetWindowRect(taskbar, out taskbarRect))
            {
                var screen = Screen.PrimaryScreen.Bounds;
                taskbarRect = new NativeMethods.RECT
                {
                    Left = screen.Left,
                    Right = screen.Right,
                    Top = screen.Bottom - 48,
                    Bottom = screen.Bottom
                };
            }

            var tray = taskbar == IntPtr.Zero ? IntPtr.Zero : NativeMethods.FindWindowEx(taskbar, IntPtr.Zero, "TrayNotifyWnd", null);
            NativeMethods.RECT trayRect;
            if (tray == IntPtr.Zero || !NativeMethods.GetWindowRect(tray, out trayRect))
            {
                trayRect = new NativeMethods.RECT
                {
                    Left = taskbarRect.Right - Math.Max(250, taskbarRect.Height * 5),
                    Right = taskbarRect.Right,
                    Top = taskbarRect.Top,
                    Bottom = taskbarRect.Bottom
                };
            }

            if (!force && RectEquals(taskbarRect, lastTaskbar) && RectEquals(trayRect, lastTray))
            {
                NativeMethods.SetWindowPos(Handle, NativeMethods.HWND_TOPMOST, Left, Top, Width, Height,
                    NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);
                return;
            }

            lastTaskbar = taskbarRect;
            lastTray = trayRect;

            var horizontal = taskbarRect.Width >= taskbarRect.Height;
            int width;
            int height;
            int x;
            int y;

            if (horizontal)
            {
                height = Math.Max(34, taskbarRect.Height - Math.Max(8, taskbarRect.Height / 5));
                // Leave enough room for two labels plus a full three-digit value
                // such as "100%" at high-DPI taskbar sizes.
                width = Math.Max(220, Math.Min(250, taskbarRect.Height * 3));
                // Windows 11's weather/widgets button is rendered by the taskbar's
                // XAML host and does not expose a stable child HWND. Anchor to its
                // standard left-side footprint, then allow a saved drag offset.
                var weatherWidth = Math.Max(112, (int)Math.Round(taskbarRect.Height * 1.55));
                x = taskbarRect.Left + weatherWidth + Math.Max(6, taskbarRect.Height / 10) + settings.HorizontalOffset;
                y = taskbarRect.Top + (taskbarRect.Height - height) / 2;
                x = Math.Max(taskbarRect.Left + 4, Math.Min(x, taskbarRect.Right - width - 4));
            }
            else
            {
                width = Math.Max(34, taskbarRect.Width - 8);
                height = 84;
                x = taskbarRect.Left + (taskbarRect.Width - width) / 2;
                y = trayRect.Top - height - 6;
            }

            NativeMethods.SetWindowPos(Handle, NativeMethods.HWND_TOPMOST, x, y, width, height,
                NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);
            Invalidate();
        }

        private static bool RectEquals(NativeMethods.RECT a, NativeMethods.RECT b)
        {
            return a.Left == b.Left && a.Top == b.Top && a.Right == b.Right && a.Bottom == b.Bottom;
        }

        private void OnSnapshotChanged(QuotaSnapshot value)
        {
            if (IsDisposed)
            {
                return;
            }

            if (InvokeRequired)
            {
                BeginInvoke(new Action<QuotaSnapshot>(OnSnapshotChanged), value);
                return;
            }

            if (value.Error != null && snapshot != null && (snapshot.FiveHour != null || snapshot.Weekly != null))
            {
                snapshot.Error = value.Error;
                snapshot.UpdatedAtLocal = value.UpdatedAtLocal;
            }
            else
            {
                snapshot = value;
            }
            UpdateToolTip();
            Invalidate();
        }

        private void UpdateToolTip()
        {
            var chinese = IsChinese;
            var lines = chinese ? "Codex 剩余额度" : "Codex quota remaining";
            if (snapshot.FiveHour != null)
            {
                lines += Environment.NewLine + (chinese ? "5 小时：" : "5 hours: ") + snapshot.FiveHour.RemainingPercent.ToString(CultureInfo.InvariantCulture) + "%" + FormatReset(snapshot.FiveHour);
            }
            if (snapshot.Weekly != null)
            {
                lines += Environment.NewLine + (chinese ? "本周：" : "Weekly: ") + snapshot.Weekly.RemainingPercent.ToString(CultureInfo.InvariantCulture) + "%" + FormatReset(snapshot.Weekly);
            }
            if (!string.IsNullOrWhiteSpace(snapshot.Error))
            {
                lines += Environment.NewLine + LocalizeError(snapshot.Error);
            }
            lines += Environment.NewLine + (chinese ? "更新：" : "Updated: ") + snapshot.UpdatedAtLocal.ToString("HH:mm:ss", CultureInfo.CurrentCulture);
            lines += Environment.NewLine + (chinese
                ? "双击刷新 · 右键菜单 · 拖动微调位置"
                : "Double-click to refresh · Right-click for menu · Drag to move");
            toolTip.SetToolTip(this, lines);
        }

        private string FormatReset(QuotaWindow window)
        {
            return window.ResetsAtLocal.HasValue
                ? (IsChinese
                    ? "（" + window.ResetsAtLocal.Value.ToString("M/d HH:mm", CultureInfo.CurrentCulture) + " 重置）"
                    : " (resets " + window.ResetsAtLocal.Value.ToString("M/d HH:mm", CultureInfo.CurrentCulture) + ")")
                : string.Empty;
        }

        private string LocalizeError(string error)
        {
            if (IsChinese)
            {
                return error;
            }
            if (error.IndexOf("正在连接", StringComparison.Ordinal) >= 0)
            {
                return "Connecting to Codex…";
            }
            if (error.IndexOf("正在重试", StringComparison.Ordinal) >= 0)
            {
                return "Connection lost; retrying…";
            }
            if (error.IndexOf("未找到", StringComparison.Ordinal) >= 0)
            {
                return "Codex was not found.";
            }
            if (error.IndexOf("额度", StringComparison.Ordinal) >= 0)
            {
                return "Quota data is currently unavailable.";
            }
            return error;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            var graphics = e.Graphics;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            using (var path = RoundedRectangle(new Rectangle(0, 0, Width - 1, Height - 1), Math.Max(7, Height / 5)))
            using (var background = new SolidBrush(Color.FromArgb(35, 35, 36)))
            using (var border = new Pen(Color.FromArgb(63, 63, 65)))
            {
                graphics.FillPath(background, path);
                graphics.DrawPath(border, path);
            }

            var center = Width / 2;
            using (var divider = new Pen(Color.FromArgb(58, 58, 60)))
            {
                graphics.DrawLine(divider, center, 8, center, Height - 8);
            }

            DrawQuota(graphics, new Rectangle(0, 0, center, Height), "5H", snapshot.FiveHour);
            DrawQuota(graphics, new Rectangle(center, 0, Width - center, Height), IsChinese ? "周" : "W", snapshot.Weekly);

            if (snapshot.FiveHour == null && snapshot.Weekly == null)
            {
                using (var font = new Font("Microsoft YaHei UI", Math.Max(7f, Height / 8f), FontStyle.Regular, GraphicsUnit.Pixel))
                using (var brush = new SolidBrush(Color.FromArgb(180, 180, 183)))
                {
                    var text = IsChinese
                        ? (snapshot.Error == null ? "正在读取额度…" : "额度暂不可用")
                        : (snapshot.Error == null ? "Loading quota…" : "Quota unavailable");
                    graphics.DrawString(text, font, brush, new RectangleF(0, 0, Width, Height), CenterFormat());
                }
            }
        }

        private void DrawQuota(Graphics graphics, Rectangle area, string label, QuotaWindow window)
        {
            if (window == null)
            {
                if (snapshot.FiveHour != null || snapshot.Weekly != null)
                {
                    var missingLabelWidth = Math.Max(22, area.Width / 4);
                    using (var labelFont = new Font("Segoe UI", Math.Max(9f, Height / 4.7f), FontStyle.Bold, GraphicsUnit.Pixel))
                    using (var valueFont = new Font("Segoe UI", Math.Max(14f, Height / 2.9f), FontStyle.Bold, GraphicsUnit.Pixel))
                    using (var brush = new SolidBrush(Color.FromArgb(132, 132, 136)))
                    {
                        var textTop = Math.Max(4, Height / 8);
                        graphics.DrawString(label, labelFont, brush,
                            new RectangleF(area.Left + 6, textTop, missingLabelWidth, Height - textTop * 2), CenterFormat());
                        graphics.DrawString("--", valueFont, brush,
                            new RectangleF(area.Left + missingLabelWidth - 1, textTop - 1, area.Width - missingLabelWidth - 4, Height - textTop * 2), CenterFormat());
                    }
                }
                return;
            }

            var remaining = window.RemainingPercent;
            var accent = AccentFor(remaining);
            var labelWidth = Math.Max(22, area.Width / 4);
            var barHeight = Math.Max(3, Height / 14);
            var barX = area.Left + 8;
            var barWidth = area.Width - 16;
            var barY = area.Bottom - barHeight - Math.Max(5, Height / 9);

            using (var labelFont = new Font("Segoe UI", Math.Max(9f, Height / 4.7f), FontStyle.Bold, GraphicsUnit.Pixel))
            using (var valueFont = new Font("Segoe UI", Math.Max(14f, Height / 2.9f), FontStyle.Bold, GraphicsUnit.Pixel))
            using (var labelBrush = new SolidBrush(Color.FromArgb(176, 176, 180)))
            using (var valueBrush = new SolidBrush(Color.FromArgb(245, 245, 247)))
            {
                var textTop = Math.Max(4, Height / 8);
                graphics.DrawString(label, labelFont, labelBrush,
                    new RectangleF(area.Left + 6, textTop, labelWidth, barY - textTop), CenterFormat());
                graphics.DrawString(remaining.ToString(CultureInfo.InvariantCulture) + "%", valueFont, valueBrush,
                    new RectangleF(area.Left + labelWidth - 1, textTop - 1, area.Width - labelWidth - 4, barY - textTop + 2), CenterFormat());
            }

            using (var track = new SolidBrush(Color.FromArgb(73, 73, 76)))
            using (var fill = new SolidBrush(accent))
            {
                graphics.FillRectangle(track, barX, barY, barWidth, barHeight);
                graphics.FillRectangle(fill, barX, barY, Math.Max(0, (int)Math.Round(barWidth * remaining / 100.0)), barHeight);
            }
        }

        private static StringFormat CenterFormat()
        {
            return new StringFormat
            {
                Alignment = StringAlignment.Center,
                LineAlignment = StringAlignment.Center,
                Trimming = StringTrimming.EllipsisCharacter,
                FormatFlags = StringFormatFlags.NoWrap
            };
        }

        private static Color AccentFor(int remaining)
        {
            if (remaining <= 20)
            {
                return Color.FromArgb(255, 86, 86);
            }
            if (remaining <= 50)
            {
                return Color.FromArgb(255, 184, 76);
            }
            return Color.FromArgb(44, 201, 126);
        }

        private static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
        {
            var diameter = radius * 2;
            var path = new GraphicsPath();
            path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
            path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
            path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private void OnWidgetMouseDown(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left)
            {
                return;
            }
            dragging = true;
            dragStartMouse = Cursor.Position;
            dragStartOffset = settings.HorizontalOffset;
            Capture = true;
        }

        private void OnWidgetMouseMove(object sender, MouseEventArgs e)
        {
            if (!dragging)
            {
                return;
            }
            var delta = Cursor.Position.X - dragStartMouse.X;
            settings.HorizontalOffset = dragStartOffset + delta;
            NativeMethods.SetWindowPos(Handle, NativeMethods.HWND_TOPMOST, Left + delta, Top, Width, Height,
                NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);
            dragStartMouse = Cursor.Position;
            dragStartOffset = settings.HorizontalOffset;
        }

        private void OnWidgetMouseUp(object sender, MouseEventArgs e)
        {
            if (!dragging)
            {
                return;
            }
            dragging = false;
            Capture = false;
            settings.Save();
            PositionOverTaskbar(true);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            positionTimer.Stop();
            positionTimer.Dispose();
            toolTip.Dispose();
            menu.Dispose();
            client.Dispose();
            base.OnFormClosed(e);
        }
    }
}
