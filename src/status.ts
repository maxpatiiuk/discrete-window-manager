let statusModal: Modal | undefined = undefined;
let statusVisible = false;

function getStatusText() {
  const screens = Screen.all();
  const screenLabelById = new Map<string, string>();

  // No performance.now()
  // Performance seems to degrade quickly
  if (1 == 1) {
    return screens
      .map((screen) => {
        const frame = screen.frame();
        const spaces = screen.spaces();
        return `${screen.identifier()}: ${frame.width}x${frame.height} (${frame.x},${frame.y})`;
      })
      .join("\n");
  }

  screens.forEach((screen, index) => {
    screenLabelById.set(screen.identifier(), `display-${index + 1}`);
  });

  const displaysByApp = new Map<string, Set<string>>();

  Window.all({ visible: true })
    .filter((window) => window.isNormal())
    .forEach((window) => {
      const appName = window.app().name();
      const screen = window.screen();
      if (!screen) return;

      const existing = displaysByApp.get(appName) ?? new Set<string>();
      existing.add(screen.identifier());
      displaysByApp.set(appName, existing);
    });

  const rows = [...displaysByApp.entries()]
    .map(([appName, displayIds]) => {
      const displays = [...displayIds]
        .map((id) => screenLabelById.get(id) ?? "display-?")
        .sort()
        .join(", ");

      return `${appName.padEnd(24)} ${displays}`;
    })
    .sort((a, b) => a.localeCompare(b));

  return rows.length > 0 ? rows.join("\n") : "(no visible app windows)";
}

function ensureModal() {
  if (statusModal) return;

  statusModal = Modal.build({
    duration: 0,
    appearance: "dark",
    weight: 16,
    hasShadow: true,
    font: "Menlo",
    text: "",
  });
}

function renderStatus(show = false) {
  ensureModal();
  if (statusModal) {
    statusModal.text = getStatusText();

    const activeScreen = Window.focused()?.screen() ?? Screen.main();
    const screenFrame = activeScreen.visibleFrame();
    const modalFrame = statusModal.frame();
    statusModal.origin = {
      x: screenFrame.x + (screenFrame.width - modalFrame.width) / 2,
      y: screenFrame.y + (screenFrame.height - modalFrame.height) / 2,
    };

    if (show) statusModal.show();
  }
}

export function bindStatus() {
  Key.on("s", ["alt"], () => {
    ensureModal();
    statusVisible = !statusVisible;
    if (statusVisible) renderStatus(true);
    else if (statusModal) statusModal.close();
  });

  Event.on("windowDidFocus", () => {
    if (statusVisible) renderStatus();
  });
}
