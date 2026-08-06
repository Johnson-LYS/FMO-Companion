const card = document.querySelector("#dashboard-card");
const fmoFacts = document.querySelector("#fmo-facts");
const serverRegion = document.querySelector("#server-region");
const relayActivityCapsule = document.querySelector("#relay-activity-capsule");
const eventRegion = document.querySelector("#event-region");
const offlineState = document.querySelector("#offline-state");
const eventCopy = document.querySelector("#event-copy");
const voiceMeter = document.querySelector("#voice-meter");
const buttons = [...document.querySelectorAll("button[data-state]")];

const eventSamples = [
  { title: "BH4XYZ-7", occurredAt: Date.now() - 12_000, icon: "#icon-clock", label: "最近讲话活动：BH4XYZ-7，位置 OM92xx" },
  { title: "安吉 FMO 中继", meta: "连接已恢复 · 1 分钟前", icon: "#icon-server", label: "服务器连接已恢复：安吉 FMO 中继，1 分钟前" },
  { title: "OM20xx", meta: "位置已更新 · 3 分钟前", icon: "#icon-map-pin", label: "FMO 位置已更新为 OM20xx，3 分钟前" }
];

const views = {
  speaking: {
    freshness: "刚刚",
    freshnessLabel: "数据刚刚更新",
    note: "当前讲话优先固定在事件窗口，不与普通事件轮播。",
    event: { title: "BH4XYZ-7", meta: "OM92xx · 正在讲话", icon: "#icon-volume", label: "当前讲话：BH4XYZ-7，位置 OM92xx" },
    hidden: [],
    label: "已连接设备仪表盘，BH4XYZ-7 正在讲话"
  },
  events: {
    freshness: "8 秒",
    freshnessLabel: "数据 8 秒前更新",
    note: "没有讲话时，单行窗口纵向切换最新真实事件。",
    event: eventSamples[0],
    hidden: [],
    label: "已连接设备仪表盘，正在显示最近事件"
  },
  partial: {
    freshness: "刚刚",
    freshnessLabel: "数据刚刚更新，部分字段暂不可用",
    note: "字段缺失时直接隐藏并回流版式，不显示 0 或破折号。",
    event: { title: "暂无新事件", meta: "事件连接正常", icon: "#icon-clock", label: "事件连接正常，暂无新事件" },
    hidden: ["filter-fact"],
    label: "已连接设备仪表盘，部分信息暂不可用"
  },
  offline: {
    freshness: "离线",
    freshnessLabel: "设备已离线",
    note: "离线后只保留设备识别，不把过期值继续表现为实时状态。",
    event: null,
    hidden: [],
    label: "设备 BI8SYN 已断开，等待自动重连"
  }
};

let selectedState = "speaking";
let eventIndex = 0;
let ticker;
let clockTicker;
let currentEvent;

function elapsedMeta(event) {
  if (!event.occurredAt) return event.meta;
  const seconds = Math.max(0, Math.floor((Date.now() - event.occurredAt) / 1000));
  return seconds < 60 ? `OM92xx · ${seconds} 秒前` : `OM92xx · ${Math.floor(seconds / 60)} 分钟前`;
}

function updateEventClock() {
  if (!currentEvent) return;
  document.querySelector("#event-meta").textContent = elapsedMeta(currentEvent);
}

function renderEvent(event, animate = false) {
  if (!event) return;

  const previousEvent = currentEvent;

  const update = () => {
    currentEvent = event;
    document.querySelector("#event-title").textContent = event.title;
    updateEventClock();
    document.querySelector("#event-icon-use").setAttribute("href", event.icon);
    eventRegion.setAttribute("aria-label", event.label);
  };

  if (!animate || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    update();
    return;
  }

  const speakerChanged = previousEvent && previousEvent.title !== event.title;
  const iconChanged = previousEvent && previousEvent.icon !== event.icon;
  if (!speakerChanged && iconChanged) {
    eventRegion.classList.add("is-icon-changing");
    window.setTimeout(() => {
      update();
      eventRegion.classList.remove("is-icon-changing");
    }, 130);
    return;
  }
  if (!speakerChanged) {
    update();
    return;
  }

  eventRegion.classList.add("is-exiting");
  window.setTimeout(() => {
    update();
    eventRegion.classList.remove("is-exiting");
    eventRegion.classList.add("is-entering");
    void eventCopy.offsetHeight;
    eventRegion.classList.remove("is-entering");
  }, 170);
}

function stopTicker() {
  window.clearInterval(ticker);
  window.clearInterval(clockTicker);
  ticker = undefined;
  clockTicker = undefined;
}

function startTicker() {
  stopTicker();
  if (selectedState !== "events" || document.hidden) return;

  ticker = window.setInterval(() => {
    eventIndex = (eventIndex + 1) % eventSamples.length;
    renderEvent(eventSamples[eventIndex], true);
  }, 3400);
  clockTicker = window.setInterval(updateEventClock, 1000);
}

function selectState(stateName) {
  const view = views[stateName];
  if (!view) return;

  selectedState = stateName;
  card.dataset.state = stateName;
  card.setAttribute("aria-label", view.label);
  document.querySelector("#freshness").textContent = view.freshness;
  document.querySelector("#freshness-wrap").setAttribute("aria-label", view.freshnessLabel);
  document.querySelector("#state-note").textContent = view.note;

  ["grid-fact", "filter-fact"].forEach((id) => {
    document.getElementById(id).hidden = view.hidden.includes(id);
  });

  const isOffline = stateName === "offline";
  fmoFacts.hidden = isOffline;
  serverRegion.hidden = isOffline;
  eventRegion.hidden = isOffline;
  relayActivityCapsule.hidden = isOffline;
  offlineState.hidden = !isOffline;
  voiceMeter.hidden = stateName !== "speaking";

  if (view.event) renderEvent(view.event, true);
  buttons.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.state === stateName)));
  startTicker();
}

buttons.forEach((button) => button.addEventListener("click", () => selectState(button.dataset.state)));
document.addEventListener("visibilitychange", startTicker);
selectState("speaking");
