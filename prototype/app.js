(() => {
  "use strict";

  const state = {
    screen: "home",
    connection: "idle",
    detail: null,
    detailHistory: [],
    discoveryTimer: null,
    toastTimer: null,
  };

  const titles = {
    home: "首页",
    network: "FMO 网络",
    qso: "QSO",
    settings: "设置",
  };

  const elements = {
    phone: document.querySelector("#phoneFrame"),
    content: document.querySelector("#appContent"),
    appHeader: document.querySelector("#appHeader"),
    backButton: document.querySelector("#backButton"),
    screenTitle: document.querySelector("#screenTitle"),
    headerStatus: document.querySelector("#headerStatus"),
    hero: document.querySelector("#deviceHero"),
    heroState: document.querySelector("#heroState"),
    heroTitle: document.querySelector("#heroTitle"),
    heroDescription: document.querySelector("#heroDescription"),
    discoverButton: document.querySelector("#discoverButton"),
    deviceEmpty: document.querySelector("#deviceEmpty"),
    discoveredDevice: document.querySelector("#discoveredDevice"),
    coordinateCard: document.querySelector("#coordinateCard"),
    syncButton: document.querySelector("#syncButton"),
    deviceCoordinate: document.querySelector("#deviceCoordinate"),
    onboardingModal: document.querySelector("#onboardingModal"),
    manualModal: document.querySelector("#manualModal"),
    diagnosticsModal: document.querySelector("#diagnosticsModal"),
    rebootModal: document.querySelector("#rebootModal"),
    webPreviewModal: document.querySelector("#webPreviewModal"),
    adminConfirmModal: document.querySelector("#adminConfirmModal"),
    diagnosticSummary: document.querySelector("#diagnosticSummary"),
    toast: document.querySelector("#toast"),
  };

  const wait = (milliseconds) => new Promise((resolve) => window.setTimeout(resolve, milliseconds));

  function setActiveScreen(screen) {
    state.screen = screen;
    state.detail = null;
    state.detailHistory = [];
    elements.screenTitle.textContent = titles[screen];
    document.querySelectorAll("[data-screen]").forEach((section) => {
      section.classList.toggle("is-active", section.dataset.screen === screen);
    });
    document.querySelectorAll("[data-tab]").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.tab === screen);
      button.setAttribute("aria-current", button.dataset.tab === screen ? "page" : "false");
    });
    document.querySelectorAll("[data-detail]").forEach((section) => section.classList.remove("is-active"));
    elements.backButton.hidden = true;
    elements.headerStatus.hidden = screen !== "home";
    elements.content.scrollTo({ top: 0, behavior: "smooth" });
  }

  function showDetail(detail, shouldPush = true) {
    const target = document.querySelector(`[data-detail="${detail}"]`);
    if (!target) return;
    if (shouldPush && state.detail) state.detailHistory.push(state.detail);
    document.querySelectorAll("[data-screen], [data-detail]").forEach((section) => section.classList.remove("is-active"));
    target.classList.add("is-active");
    state.detail = detail;
    elements.screenTitle.textContent = target.dataset.title;
    elements.backButton.hidden = false;
    elements.headerStatus.hidden = true;
    elements.content.scrollTo({ top: 0, behavior: "smooth" });
  }

  function navigateBack() {
    const previousDetail = state.detailHistory.pop();
    if (previousDetail) {
      showDetail(previousDetail, false);
    } else {
      setActiveScreen(state.screen);
    }
  }

  function updateHeaderStatus(label, kind = "idle") {
    elements.headerStatus.querySelector("span:last-child").textContent = label;
    elements.headerStatus.classList.toggle("is-connected", kind === "connected");
    elements.headerStatus.classList.toggle("is-error", kind === "error");
  }

  function setConnectionState(nextState) {
    state.connection = nextState;
    elements.hero.classList.remove("is-searching", "is-connected", "is-error");

    if (nextState === "searching") {
      elements.discoverButton.dataset.action = "discover";
      elements.hero.classList.add("is-searching");
      elements.heroState.textContent = "正在搜索 · 10 秒内";
      elements.heroTitle.textContent = "正在浏览局域网服务";
      elements.heroDescription.textContent = "我们会识别名称包含 FMO 的设备，并解析可连接地址。";
      elements.discoverButton.querySelector("span:first-child").textContent = "停止搜索";
      elements.deviceEmpty.classList.add("is-searching");
      elements.deviceEmpty.querySelector("strong").textContent = "正在发现 FMO…";
      elements.deviceEmpty.querySelector("p").textContent = "保持此页面打开，发现结果会自动出现。";
      elements.discoveredDevice.hidden = true;
      elements.coordinateCard.hidden = true;
      updateHeaderStatus("发现中");
      return;
    }

    if (nextState === "found") {
      elements.discoverButton.dataset.action = "discover";
      elements.heroState.textContent = "发现 1 台设备";
      elements.heroTitle.textContent = "选择设备建立连接";
      elements.heroDescription.textContent = "已发现示例设备 FMO-7C2A，点击列表即可开始 GEO WebSocket 握手。";
      elements.discoverButton.querySelector("span:first-child").textContent = "重新发现";
      elements.deviceEmpty.hidden = true;
      elements.discoveredDevice.hidden = false;
      updateHeaderStatus("待连接");
      return;
    }

    if (nextState === "connected") {
      elements.hero.classList.add("is-connected");
      elements.heroState.textContent = "已连接";
      elements.heroTitle.textContent = "FMO-7C2A 已准备好";
      elements.heroDescription.textContent = "GEO WebSocket 响应正常。你可以读取盒子坐标，并由你主动同步 iPhone 位置。";
      elements.discoverButton.querySelector("span:first-child").textContent = "查看诊断";
      elements.discoverButton.dataset.action = "open-diagnostics";
      elements.deviceEmpty.hidden = true;
      elements.discoveredDevice.hidden = false;
      elements.coordinateCard.hidden = false;
      updateHeaderStatus("已连接", "connected");
      setDiagnosticState("connected");
      return;
    }

    if (nextState === "offline") {
      elements.hero.classList.add("is-error");
      elements.heroState.textContent = "连接中断";
      elements.heroTitle.textContent = "无法完成 WebSocket 握手";
      elements.heroDescription.textContent = "Wi-Fi 与主机解析正常，但 GEO 接口没有响应。查看诊断可获得下一步建议。";
      elements.discoverButton.querySelector("span:first-child").textContent = "查看诊断";
      elements.discoverButton.dataset.action = "open-diagnostics";
      elements.deviceEmpty.hidden = true;
      elements.discoveredDevice.hidden = false;
      elements.coordinateCard.hidden = true;
      updateHeaderStatus("需处理", "error");
      setDiagnosticState("offline");
      return;
    }

    elements.heroState.textContent = "等待连接";
    elements.heroTitle.textContent = "让 iPhone 找到你的 FMO";
    elements.heroDescription.textContent = "确保手机与盒子位于同一 Wi-Fi。自动发现失败时，也可以手动输入地址。";
    elements.discoverButton.querySelector("span:first-child").textContent = "开始发现";
    elements.discoverButton.dataset.action = "discover";
    elements.deviceEmpty.hidden = false;
    elements.deviceEmpty.classList.remove("is-searching");
    elements.deviceEmpty.querySelector("strong").textContent = "尚未开始搜索";
    elements.deviceEmpty.querySelector("p").textContent = "发现窗口最长 10 秒，结果会显示在这里。";
    elements.discoveredDevice.hidden = true;
    elements.coordinateCard.hidden = true;
    updateHeaderStatus("未连接");
    setDiagnosticState("idle");
  }

  function startDiscovery() {
    if (state.connection === "searching") {
      window.clearTimeout(state.discoveryTimer);
      setConnectionState("idle");
      showToast("已停止设备发现", "—");
      return;
    }

    elements.deviceEmpty.hidden = false;
    setConnectionState("searching");
    state.discoveryTimer = window.setTimeout(() => {
      setConnectionState("found");
      showToast("发现 1 台示例设备");
    }, 1350);
  }

  async function connectDevice(label = "FMO-7C2A") {
    setActiveScreen("home");
    elements.heroState.textContent = "正在连接";
    elements.heroTitle.textContent = `正在连接 ${label}`;
    elements.heroDescription.textContent = "正在解析主机并建立 GEO WebSocket…";
    updateHeaderStatus("连接中");
    closeAllModals();
    await wait(800);
    setConnectionState("connected");
    showToast("连接成功，坐标已读取");
  }

  async function syncCoordinate() {
    if (state.connection !== "connected") {
      showToast("请先连接 FMO", "!");
      return;
    }
    elements.syncButton.disabled = true;
    elements.syncButton.classList.add("is-loading");
    elements.syncButton.querySelector(".button-label").textContent = "正在同步";
    await wait(900);
    elements.deviceCoordinate.textContent = "30.000420, 120.000310";
    elements.syncButton.disabled = false;
    elements.syncButton.classList.remove("is-loading");
    elements.syncButton.querySelector(".button-label").textContent = "再次同步";
    showToast("坐标已同步到示例设备");
  }

  function showModal(modal) {
    Array.from(document.querySelectorAll(".modal-backdrop"))
      .filter((item) => item !== modal)
      .forEach(hideModal);
    window.clearTimeout(modal._hideTimer);
    modal.hidden = false;
    requestAnimationFrame(() => modal.classList.add("is-visible"));
    window.setTimeout(() => {
      const focusTarget = modal.querySelector("input, button:not([disabled])");
      focusTarget?.focus();
    }, 220);
  }

  function hideModal(modal) {
    if (!modal || modal.hidden) return;
    window.clearTimeout(modal._hideTimer);
    modal.classList.remove("is-visible");
    modal._hideTimer = window.setTimeout(() => { modal.hidden = true; }, 220);
  }

  function closeAllModals() {
    document.querySelectorAll(".modal-backdrop").forEach(hideModal);
  }

  function showToast(message, symbol = "✓") {
    window.clearTimeout(state.toastTimer);
    elements.toast.querySelector("span").textContent = symbol;
    elements.toast.querySelector("p").textContent = message;
    elements.toast.classList.add("is-visible");
    state.toastTimer = window.setTimeout(() => elements.toast.classList.remove("is-visible"), 2200);
  }

  function setDiagnosticStep(key, status, detail) {
    const row = document.querySelector(`[data-diag="${key}"]`);
    const stateBadge = row.querySelector(".diag-state");
    stateBadge.className = `diag-state ${status}`;
    stateBadge.textContent = status === "good" ? "✓" : status === "bad" ? "!" : "—";
    row.querySelector("small").textContent = detail;
  }

  function setDiagnosticState(mode) {
    if (mode === "connected") {
      elements.diagnosticSummary.textContent = "设备端点已脱敏，四项检查均通过。未包含精确位置或任何凭据。";
      setDiagnosticStep("wifi", "good", "已连接适用的局域网");
      setDiagnosticStep("host", "good", "fmo.local 解析成功");
      setDiagnosticStep("http", "good", "官方后台可达");
      setDiagnosticStep("ws", "good", "握手与响应正常");
      return;
    }
    if (mode === "offline") {
      elements.diagnosticSummary.textContent = "GEO WebSocket 握手失败。建议确认盒子在线，或在官方后台检查服务状态。";
      setDiagnosticStep("wifi", "good", "已连接适用的局域网");
      setDiagnosticStep("host", "good", "fmo.local 解析成功");
      setDiagnosticStep("http", "good", "官方后台可达");
      setDiagnosticStep("ws", "bad", "握手失败，可稍后重试");
      return;
    }
    elements.diagnosticSummary.textContent = "尚未连接设备，可先自动发现或手动输入地址。";
    setDiagnosticStep("wifi", "neutral", "等待检测");
    setDiagnosticStep("host", "neutral", "等待设备地址");
    setDiagnosticStep("http", "neutral", "等待连接");
    setDiagnosticStep("ws", "neutral", "等待握手");
  }

  function applyTheme(theme, button) {
    const shouldUseDark = theme === "dark" || (theme === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
    elements.phone.classList.toggle("theme-dark", shouldUseDark);
    document.querySelectorAll("[data-theme]").forEach((item) => item.classList.toggle("is-selected", item === button));
    showToast(`${button.textContent.trim()}外观已应用`, "◐");
  }

  async function simulateReconnect(button) {
    const original = button.textContent;
    button.disabled = true;
    button.textContent = "已离开局域网 · 暂停发送";
    showToast("检测到网络离开，已暂停高频重试", "—");
    await wait(1100);
    button.textContent = "网络恢复 · 正在退避重连…";
    await wait(950);
    button.textContent = "已恢复连接并继续同步";
    showToast("局域网已恢复，位置同步继续");
    await wait(1000);
    button.textContent = original;
    button.disabled = false;
  }

  function openWebPreview(portal) {
    const isQso = portal === "qso";
    document.querySelector("#webPreviewURL").textContent = isQso ? "http://fmo.local/qso.html" : "http://fmo.local";
    document.querySelector("#webPreviewIcon").textContent = isQso ? "Q" : "FM";
    document.querySelector("#webPreviewTitle").textContent = isQso ? "QSO 下载页面" : "FMO 官方后台";
    document.querySelector("#webPreviewDescription").textContent = isQso
      ? "用户可主动下载 SQLite 数据库与签名文件，随后回到 App 导入。"
      : "受限浏览器预览。不会注入脚本或模拟未公开接口。";
    showModal(elements.webPreviewModal);
  }

  async function simulateCommand(command) {
    const result = document.querySelector("#commandResult");
    const counter = document.querySelector("#counterValue");
    counter.textContent = String(Number(counter.textContent) + 1).padStart(4, "0");
    result.querySelector("span").textContent = "…";
    result.querySelector("strong").textContent = `正在签名 ${command}`;
    result.querySelector("small").textContent = "Time Slot 与 Counter 已锁定，正在生成 HMAC。";
    await wait(700);
    result.querySelector("strong").textContent = "命令已发送，等待 ACK";
    result.querySelector("small").textContent = "标准 APRS 消息已进入等待状态。";
    await wait(900);
    result.querySelector("span").textContent = "✓";
    result.querySelector("strong").textContent = `${command} 已确认`;
    result.querySelector("small").textContent = "收到设备 ACK；原型未发送真实命令。";
    showToast(`${command} ACK 演示完成`);
  }

  async function simulateImport(button) {
    const wrapper = document.querySelector("#importProgress");
    const progress = wrapper.querySelector("progress");
    const percent = document.querySelector("#importPercent");
    const stepKeys = ["schema", "hash", "signature", "index"];
    wrapper.hidden = false;
    button.disabled = true;
    button.textContent = "正在读取示例文件";
    for (let value = 0; value <= 100; value += 10) {
      progress.value = value;
      percent.textContent = `${value}%`;
      const completedSteps = Math.min(stepKeys.length, Math.floor(value / 25));
      stepKeys.forEach((key, index) => {
        const badge = document.querySelector(`[data-import-step="${key}"] .check`);
        badge.className = `check ${index < completedSteps ? "good" : "neutral"}`;
        badge.textContent = index < completedSteps ? "✓" : "—";
      });
      await wait(130);
    }
    stepKeys.forEach((key) => {
      const badge = document.querySelector(`[data-import-step="${key}"] .check`);
      badge.className = "check good";
      badge.textContent = "✓";
    });
    button.disabled = false;
    button.textContent = "重新选择示例文件";
    showToast("已导入 1,284 条示例 QSO");
  }

  async function sendMessage() {
    const input = document.querySelector("#messageInput");
    const value = input.value.trim();
    if (!value) {
      showToast("请输入消息内容", "!");
      return;
    }
    const bubble = document.createElement("div");
    bubble.className = "message-bubble outgoing";
    bubble.textContent = value;
    const status = document.createElement("small");
    status.textContent = "等待 ACK · 刚刚";
    bubble.append(status);
    document.querySelector("#conversationThread").append(bubble);
    input.value = "";
    showToast("消息已发送，等待 ACK", "↑");
    await wait(1100);
    status.textContent = "ACK 02 · 刚刚";
    showToast("已收到 APRS ACK");
  }

  async function simulateSimpleCheck(button, working, complete) {
    const original = button.textContent;
    button.disabled = true;
    button.textContent = working;
    await wait(850);
    button.textContent = original;
    button.disabled = false;
    showToast(complete);
  }

  document.addEventListener("click", async (event) => {
    const tab = event.target.closest("[data-tab]");
    if (tab) {
      setActiveScreen(tab.dataset.tab);
      return;
    }

    const theme = event.target.closest("[data-theme]");
    if (theme) {
      applyTheme(theme.dataset.theme, theme);
      return;
    }

    const chip = event.target.closest(".chip");
    if (chip) {
      chip.parentElement.querySelectorAll(".chip").forEach((item) => item.classList.toggle("is-selected", item === chip));
      showToast(`已筛选：${chip.textContent.trim()}`, "⌖");
      return;
    }

    const selectable = event.target.closest(".selectable-option");
    if (selectable) {
      selectable.parentElement.querySelectorAll(".selectable-option").forEach((item) => item.classList.toggle("is-selected", item === selectable));
      showToast(`已选择：${selectable.querySelector("strong").textContent}`, "✓");
      return;
    }

    const inlineChoice = event.target.closest(".inline-tabs button, .failure-chips button");
    if (inlineChoice) {
      inlineChoice.parentElement.querySelectorAll("button").forEach((item) => item.classList.toggle("is-selected", item === inlineChoice));
      showToast(`已切换：${inlineChoice.textContent.trim()}`, "◇");
      return;
    }

    const mode = event.target.closest(".mode-option");
    if (mode) {
      document.querySelectorAll(".mode-option").forEach((item) => item.classList.toggle("is-selected", item === mode));
      mode.querySelector("input").checked = true;
      showToast(`已选择${mode.querySelector("strong").textContent}模式`, "⌁");
      return;
    }

    const actionTarget = event.target.closest("[data-action]");
    if (!actionTarget) return;

    const action = actionTarget.dataset.action;
    if (action === "back") {
      navigateBack();
    } else if (action === "open-detail") {
      showDetail(actionTarget.dataset.target);
    } else if (action === "finish-onboarding") {
      hideModal(elements.onboardingModal);
      showToast("权限用途说明已完成");
    } else if (action === "discover") {
      startDiscovery();
    } else if (action === "connect") {
      await connectDevice();
    } else if (action === "open-manual") {
      showModal(elements.manualModal);
    } else if (action === "manual-connect") {
      const input = document.querySelector("#manualHost");
      const host = input.value.trim();
      if (!host) {
        input.focus();
        showToast("请输入主机名或 IPv4 地址", "!");
      } else {
        await connectDevice(host);
      }
    } else if (action === "sync-coordinate") {
      await syncCoordinate();
    } else if (action === "open-diagnostics") {
      showModal(elements.diagnosticsModal);
    } else if (action === "open-reboot") {
      showModal(elements.rebootModal);
    } else if (action === "confirm-reboot") {
      hideModal(elements.rebootModal);
      showToast("身份确认演示完成，未发送命令", "↻");
    } else if (action === "simulate-permission") {
      const banner = actionTarget.previousElementSibling;
      banner.className = "status-banner info-banner";
      banner.querySelector("span").textContent = "✓";
      banner.querySelector("strong").textContent = "后台定位授权演示完成";
      banner.querySelector("small").textContent = "正式版授权结果由系统决定，原型未请求真实权限。";
      showToast("已演示系统授权结果");
    } else if (action === "simulate-reconnect") {
      await simulateReconnect(actionTarget);
    } else if (action === "open-web-preview") {
      openWebPreview(actionTarget.dataset.portal);
    } else if (action === "toggle-favorite") {
      actionTarget.classList.toggle("is-selected");
      actionTarget.textContent = actionTarget.classList.contains("is-selected") ? "显示全部" : "仅看收藏";
      showToast(actionTarget.classList.contains("is-selected") ? "已仅显示收藏服务器" : "已显示全部服务器", "★");
    } else if (action === "simulate-check") {
      await simulateSimpleCheck(actionTarget, "正在更新 CRL 并验证…", "信任材料已更新，验证通过");
    } else if (action === "refresh-server") {
      await simulateSimpleCheck(actionTarget, "刷新中…", "服务器状态已刷新");
    } else if (action === "confirm-admin") {
      showModal(elements.adminConfirmModal);
    } else if (action === "confirm-admin-final") {
      hideModal(elements.adminConfirmModal);
      showToast("管理员认证演示完成，未执行操作", "⌑");
    } else if (action === "save-credentials") {
      await simulateSimpleCheck(actionTarget, "正在保存到 Keychain…", "示例凭据已安全保存");
    } else if (action === "send-message") {
      await sendMessage();
    } else if (action === "simulate-command") {
      await simulateCommand(actionTarget.dataset.command);
    } else if (action === "simulate-import") {
      await simulateImport(actionTarget);
    } else if (action === "simulate-export") {
      await simulateSimpleCheck(actionTarget, "正在验证并生成…", "示例 ADIF 已生成，可通过系统分享");
    } else if (action === "test-notification") {
      await simulateSimpleCheck(actionTarget, "正在请求测试通知…", "测试通知已模拟发送");
    } else if (action === "run-shortcut") {
      showToast(`已运行：${actionTarget.querySelector("strong").textContent}`, "◇");
    } else if (action === "export-diagnostics") {
      await simulateSimpleCheck(actionTarget, "正在检查敏感字段…", "脱敏诊断预览已生成");
    } else if (action === "show-future") {
      showToast("该能力将在后续里程碑实现", "◇");
    } else if (action === "close-modal") {
      hideModal(actionTarget.closest(".modal-backdrop"));
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      const visibleModal = document.querySelector(".modal-backdrop.is-visible");
      if (visibleModal) hideModal(visibleModal);
      else if (state.detail) navigateBack();
    }
  });

  document.addEventListener("input", (event) => {
    const range = event.target.closest("input[type='range'][data-output]");
    if (!range) return;
    const output = document.querySelector(`#${range.dataset.output}`);
    output.textContent = `${range.value}${range.dataset.suffix || ""}`;
  });

  document.querySelectorAll(".modal-backdrop").forEach((backdrop) => {
    backdrop.addEventListener("click", (event) => {
      if (event.target === backdrop && backdrop !== elements.onboardingModal) hideModal(backdrop);
    });
  });

  setConnectionState("idle");
})();
