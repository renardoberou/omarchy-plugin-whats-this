"""python3 -m unittest discover -s tests"""
import importlib.machinery, importlib.util, os, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("helpd", os.path.join(HERE, "..", "bin", "omarchy-whats-this"))
spec = importlib.util.spec_from_loader("helpd", loader)
d = importlib.util.module_from_spec(spec)
loader.exec_module(d)

PRINTER = """SUPER + K                           → Keybindings
SUPER + RETURN                      → Terminal
SUPER SHIFT + RETURN                → Browser
SUPER SHIFT + B                     → Browser
SUPER + W                           → Close window
SUPER SHIFT + 1                     → Move window to workspace 1
SUPER SHIFT + 2                     → Move window to workspace 2
SUPER SHIFT + 0                     → Move window to workspace 10
SUPER SHIFT + Y                     → YouTube
SUPER SHIFT + O                     → Obsidian
"""

LUA = '''
o.bind("SUPER + RETURN", "Terminal", { omarchy = "terminal" })
o.bind("SUPER + SHIFT + RETURN", "Browser", { omarchy = "browser" })
o.bind("SUPER + SHIFT + O", "Obsidian", { launch = "obsidian", focus = "^obsidian$" })
o.bind("SUPER + SHIFT + Y", "YouTube", { webapp = "https://youtube.com/" })
o.bind("SUPER + H", "Voxtype dictation", "voxtype record toggle")
'''


class Binds(unittest.TestCase):
    def test_printer(self):
        b = d.parse_bind_printer(PRINTER)
        self.assertEqual(b["Terminal"], "SUPER + RETURN")
        self.assertEqual(b["Browser"], "SUPER SHIFT + RETURN")      # first wins
        self.assertEqual(len(b), 9)

    def test_lua_launchers(self):
        l = d.parse_lua_launchers(LUA)
        self.assertEqual([x["desc"] for x in l], ["Terminal", "Browser", "Obsidian", "YouTube"])
        self.assertEqual(l[3], {"desc": "YouTube", "kind": "webapp", "value": "https://youtube.com/"})

    def test_numbered_rows_collapse(self):
        r = d.numbered(d.parse_bind_printer(PRINTER), r"^Move window to workspace (\d+)$", "Move to workspace")
        self.assertEqual(r, {"keys": "SUPER SHIFT + 1…0", "label": "Move to workspace"})


class AppsAndLaunchers(unittest.TestCase):
    def test_desktop_parse(self):
        e = d.parse_desktop("[Desktop Entry]\nName=Ghostty\nGenericName=Terminal\nComment=A terminal emulator\n"
                            "Exec=ghostty\n[Desktop Action new]\nName=New Window\n")
        self.assertEqual(e["Name"], "Ghostty")               # action sections ignored
        self.assertEqual(e["Comment"], "A terminal emulator")

    def test_webapp_class(self):
        self.assertEqual(d.webapp_key("app.hey.com", "/calendar/weeks/"), "app.hey.com__calendar_weeks")
        yt = {"desc": "YouTube", "kind": "webapp", "value": "https://youtube.com/"}
        self.assertTrue(d.launcher_matches(yt, None, "chrome-youtube.com__-Default", "", ""))
        self.assertFalse(d.launcher_matches(yt, None, "chrome-x.com__-Default", "", ""))

    def test_terminal_and_browser(self):
        term = {"desc": "Terminal", "kind": "omarchy", "value": "terminal"}
        app = {"id": "com.mitchellh.ghostty"}
        self.assertTrue(d.launcher_matches(term, app, "com.mitchellh.ghostty", "com.mitchellh.ghostty", ""))
        br = {"desc": "Browser", "kind": "omarchy", "value": "browser"}
        self.assertTrue(d.launcher_matches(br, {"id": "google-chrome"}, "google-chrome", "", "google-chrome"))
        # a Chrome web app is not "the browser"
        self.assertFalse(d.launcher_matches(br, None, "chrome-youtube.com__-Default", "", "google-chrome"))

    def test_launch_by_name(self):
        ob = {"desc": "Obsidian", "kind": "launch", "value": "obsidian"}
        self.assertTrue(d.launcher_matches(ob, {"id": "obsidian"}, "obsidian", "", ""))


class Hit(unittest.TestCase):
    MON = {"x": 1474, "y": 768, "width": 1920, "height": 1080, "scale": 1.25,
           "activeWorkspace": {"id": 3, "name": "3"}, "specialWorkspace": {"id": 0}}

    def test_monitor_at_uses_logical_size(self):
        self.assertIs(d.monitor_at([self.MON], 1474 + 1535, 800), self.MON)
        self.assertIsNone(d.monitor_at([self.MON], 1474 + 1537, 800))

    def test_floating_over_tiled_and_workspace_filter(self):
        tiled = {"class": "a", "at": [1474, 800], "size": [1000, 800], "workspace": {"id": 3}, "floating": False, "focusHistoryID": 0}
        floating = {"class": "b", "at": [1600, 900], "size": [300, 300], "workspace": {"id": 3}, "floating": True, "focusHistoryID": 2}
        other_ws = {"class": "c", "at": [1474, 768], "size": [2000, 2000], "workspace": {"id": 5}, "floating": True, "focusHistoryID": 1}
        hit = d.window_at([tiled, floating, other_ws], self.MON, 1700, 1000)
        self.assertEqual(hit["class"], "b")
        self.assertEqual(d.window_at([tiled, other_ws], self.MON, 1700, 1000)["class"], "a")
        self.assertIsNone(d.window_at([other_ws], self.MON, 1700, 1000))

    def test_bar_layer(self):
        layers = {"eDP-1": {"levels": {"2": [{"namespace": "omarchy-bar", "x": 1474, "y": 768, "w": 1536, "h": 26}]}}}
        self.assertTrue(d.over_bar(layers, 1500, 780))
        self.assertFalse(d.over_bar(layers, 1500, 800))


class Cards(unittest.TestCase):
    def test_window_card(self):
        binds = d.parse_bind_printer(PRINTER)
        launchers = d.parse_lua_launchers(LUA)
        class FakeApps:
            def identify(self, cls, initial=""):
                return {"id": "com.mitchellh.ghostty", "Name": "Ghostty", "GenericName": "", "Comment": "A terminal emulator"}
        c = d.window_card({"class": "com.mitchellh.ghostty", "title": "~/Work"}, FakeApps(), binds, launchers,
                          "com.mitchellh.ghostty", "google-chrome")
        self.assertEqual(c["title"], "Ghostty")
        self.assertEqual(c["subtitle"], "A terminal emulator")
        self.assertEqual(c["detail"], "~/Work")
        self.assertEqual(c["sections"][0], {"heading": "Open Ghostty", "rows": [{"keys": "SUPER + RETURN", "label": "Terminal"}]})
        self.assertIn({"keys": "SUPER + W", "label": "Close window"}, c["sections"][1]["rows"])

    def test_desktop_card(self):
        c = d.desktop_card(self.__class__.MON if hasattr(self.__class__, "MON") else Hit.MON, d.parse_bind_printer(PRINTER))
        self.assertEqual(c["title"], "Workspace 3")
        self.assertIn("Keybindings", [r["label"] for r in c["sections"][0]["rows"]])


if __name__ == "__main__":
    unittest.main()


class CoachEvents(unittest.TestCase):
    """The Coach reads only Hyprland events; hypr() and emit() are stubbed."""

    def setUp(self):
        self.out = []
        self._emit, self._hypr = d.emit, d.hypr
        d.emit = lambda o: self.out.append(o)
        d.hypr = lambda cmd, as_json=True: {"x": 1600, "y": 10} if cmd == "cursorpos" else None

        class St:
            layers = {"HDMI-A-1": {"levels": {"2": [{"namespace": "omarchy-bar", "x": 1536, "y": 0, "w": 1360, "h": 26}]}}}
            def mark(self, binds=False): pass
            def refresh(self): pass

        class FakeApps:
            def identify(self, cls, initial=""):
                return {"id": "com.mitchellh.ghostty", "Name": "Ghostty"} if "ghostty" in cls else None

        binds = d.parse_bind_printer(PRINTER)
        self.coach = d.Coach(St(), {"apps": FakeApps(), "binds": binds, "launchers": d.parse_lua_launchers(LUA),
                                    "term": "com.mitchellh.ghostty", "browser": "google-chrome"})

    def tearDown(self):
        d.emit, d.hypr = self._emit, self._hypr

    def test_workspace_switch_reports_pointer_over_bar(self):
        self.coach.on_event("workspacev2", "2,2", now=10)
        self.assertEqual(self.out[-1]["event"], "workspace")
        self.assertEqual(self.out[-1]["name"], "2")
        self.assertTrue(self.out[-1]["overBar"])

    def test_window_after_menu_is_via_menu_with_its_shortcut(self):
        self.coach.on_event("openlayer", "omarchy-menu", now=10)
        self.coach.on_event("closelayer", "omarchy-menu", now=11)
        self.coach.on_event("openwindow", "abc,1,com.mitchellh.ghostty,~", now=12)
        e = self.out[-1]
        self.assertTrue(e["viaMenu"])
        self.assertEqual(e["app"], "Ghostty")
        self.assertEqual(e["launch"], {"keys": "SUPER + RETURN", "label": "Terminal"})

    def test_window_long_after_menu_is_not_via_menu(self):
        self.coach.on_event("closelayer", "omarchy-menu", now=11)
        self.coach.on_event("openwindow", "abc,1,com.mitchellh.ghostty,~", now=30)
        self.assertFalse(self.out[-1]["viaMenu"])

    def test_other_layers_are_ignored(self):
        self.coach.on_event("openlayer", "omarchy-typewriter", now=10)
        self.coach.on_event("openwindow", "abc,1,com.mitchellh.ghostty,~", now=10.5)
        self.assertFalse(self.out[-1]["viaMenu"])

    def test_args(self):
        self.assertEqual(d.parse_args(["--hover", "0", "--coach", "1"]), {"hover": False, "coach": True})
        self.assertEqual(d.parse_args([]), {"hover": True, "coach": False})
