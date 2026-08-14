(() => {
  "use strict";

  const speakers = [
    {
      callsign: "BH4XYZ", initials: "BH", grid: "PM01ab", area: "浙江省 · 湖州市附近",
      distance: 187, bearing: 42, direction: "东北", cardinal: "NE",
      accuracy: "近期位置", precise: true, mapX: 72, mapY: 25, panX: -10, panY: 7,
    },
    {
      callsign: "BG0AAA", initials: "BG", grid: "ON80ca", area: "甘肃省 · 兰州市附近",
      distance: 942, bearing: 306, direction: "西北", cardinal: "NW",
      accuracy: "大致位置", precise: false, mapX: 31, mapY: 22, panX: 11, panY: 8,
    },
    {
      callsign: "BD7ABC", initials: "BD", grid: "OL63na", area: "广东省 · 广州市附近",
      distance: 768, bearing: 173, direction: "南", cardinal: "S",
      accuracy: "近期位置", precise: true, mapX: 61, mapY: 78, panX: -5, panY: -8,
    },
    {
      callsign: "BH2SCO", initials: "BH", grid: "PN11vh", area: "辽宁省 · 沈阳市附近",
      distance: 1536, bearing: 28, direction: "东北", cardinal: "NE",
      accuracy: "大致位置", precise: false, mapX: 77, mapY: 18, panX: -13, panY: 10,
    },
  ];

  const panels = Array.from(document.querySelectorAll("[data-panel]"));
  const switches = Array.from(document.querySelectorAll("[data-view]"));
  const trackingButton = document.querySelector("[data-action='toggle-tracking']");
  const trackingStatus = document.querySelector("#trackingStatus");
  const speakerPanel = document.querySelector(".speaker-panel");
  const visualStage = document.querySelector(".visual-stage");
  const historyList = document.querySelector("#speakerHistory");
  const compassWrap = document.querySelector(".compass-wrap");
  const compassPointer = document.querySelector("#compassPointer");
  const mapCanvas = document.querySelector("#mapCanvas");
  const mapWorld = document.querySelector("#mapWorld");
  const mapMarker = document.querySelector("#mapSpeakerMarker");
  const mapGridArea = document.querySelector("#mapGridArea");
  const mapConnection = document.querySelector("#mapConnection");
  const mapDistance = document.querySelector("#mapDistance");
  const serverMarquee = document.querySelector("#serverMarquee");
  const locationMarquee = document.querySelector("#locationMarquee");
  const audioToggle = document.querySelector("[data-action='toggle-audio']");
  const audioWaveform = document.querySelector("#audioWaveform");
  const serverPicker = document.querySelector("#fullscreenServerPicker");
  const fullscreenServerName = document.querySelector("#fullscreenServerName");
  const serverSearch = serverPicker.querySelector("input[type='search']");

  let speakerIndex = 0;
  let trackingEnabled = true;
  let transitionTimer = null;
  let cameraTimer = null;
  let audioEnabled = window.localStorage.getItem("fmo-prototype-audio-enabled") === "true";
  let audioPhase = 0;
  let lastAudioFrame = 0;

  function updateAudioWaveform(phaseStep = 0) {
    audioPhase += phaseStep;
    const points = Array.from({ length: 48 }, (_, index) => {
      const x = index * (240 / 47);
      const envelope = .22 + .78 * Math.sin((index / 47) * Math.PI);
      const signal = Math.sin(index * .72 + audioPhase) * .55 + Math.sin(index * 1.63 - audioPhase * .8) * .22;
      const y = 18 - signal * envelope * 16.5;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    });
    audioWaveform?.setAttribute("points", points.join(" "));
  }

  function animateAudioWaveform(timestamp) {
    const elapsed = lastAudioFrame === 0 ? 1000 / 60 : Math.min(timestamp - lastAudioFrame, 50);
    updateAudioWaveform(elapsed * .0024);
    lastAudioFrame = timestamp;
    window.requestAnimationFrame(animateAudioWaveform);
  }

  function selectView(view) {
    switches.forEach((button) => {
      const selected = button.dataset.view === view;
      button.classList.toggle("is-selected", selected);
      button.setAttribute("aria-pressed", String(selected));
    });
    panels.forEach((panel) => {
      const selected = panel.dataset.panel === view;
      panel.hidden = !selected;
      panel.classList.toggle("is-active", selected);
    });
    if (view === "map") requestAnimationFrame(() => updateMapGeometry(speakers[speakerIndex], false));
  }

  function updateCompass(speaker) {
    compassPointer.style.transform = `translate(-50%, -50%) rotate(${speaker.bearing}deg)`;
    compassWrap.setAttribute("aria-label", `${speaker.callsign} 位于${speaker.direction}方向约 ${speaker.distance} 公里`);
    document.querySelector("#compassCardinal").textContent = speaker.direction;
    document.querySelector("#compassDegrees").textContent = `${speaker.bearing}°`;
    document.querySelector("#compassDistance").textContent = String(speaker.distance);
  }

  function updateMapGeometry(speaker, animateCamera = true) {
    const width = mapWorld.clientWidth;
    const height = mapWorld.clientHeight;
    if (!width || !height) return;

    mapMarker.style.left = `${speaker.mapX}%`;
    mapMarker.style.top = `${speaker.mapY}%`;
    mapMarker.querySelector("span").textContent = speaker.initials;
    mapMarker.querySelector("strong").textContent = speaker.callsign;
    mapGridArea.style.left = `${speaker.mapX}%`;
    mapGridArea.style.top = `${speaker.mapY}%`;
    mapGridArea.querySelector("span").textContent = speaker.grid;

    const origin = { x: width * .24, y: height * .72 };
    const target = { x: width * speaker.mapX / 100, y: height * speaker.mapY / 100 };
    const deltaX = target.x - origin.x;
    const deltaY = target.y - origin.y;
    mapConnection.style.left = `${origin.x}px`;
    mapConnection.style.top = `${origin.y}px`;
    mapConnection.style.width = `${Math.hypot(deltaX, deltaY)}px`;
    mapConnection.style.transform = `rotate(${Math.atan2(deltaY, deltaX) * 180 / Math.PI}deg)`;
    mapDistance.style.left = `${(origin.x + target.x) / 2}px`;
    mapDistance.style.top = `${(origin.y + target.y) / 2}px`;
    mapDistance.querySelector("strong").textContent = `${speaker.distance} km`;
    mapDistance.querySelector("span").textContent = `${speaker.direction} ${speaker.bearing}°`;

    if (trackingEnabled && animateCamera) {
      window.clearTimeout(cameraTimer);
      mapWorld.classList.add("is-following");
      mapWorld.style.transform = `translate3d(${speaker.panX}px, ${speaker.panY}px, 0) scale(1.025)`;
      cameraTimer = window.setTimeout(() => {
        mapWorld.style.transform = `translate3d(${speaker.panX}px, ${speaker.panY}px, 0) scale(1)`;
        mapWorld.classList.remove("is-following");
      }, 850);
    }
  }

  function prependHistory(speaker) {
    const article = document.createElement("article");
    article.innerHTML = `<span>${speaker.initials}</span><strong>${speaker.callsign}</strong><small>${speaker.area.replace(" · ", "")}</small>`;
    historyList.prepend(article);
    while (historyList.children.length > 10) historyList.lastElementChild.remove();
    historyList.scrollTop = 0;
  }

  function configureServerMarquee() {
    const track = serverMarquee?.querySelector(".server-track");
    const label = track?.querySelector("strong");
    if (!track || !label) return;
    track.querySelectorAll("strong[aria-hidden='true']").forEach((copy) => copy.remove());
    track.classList.remove("is-scrolling");
    if (label.scrollWidth <= serverMarquee.clientWidth + 1) return;
    const copy = label.cloneNode(true);
    copy.setAttribute("aria-hidden", "true");
    track.append(copy);
    track.style.setProperty("--marquee-duration", `${Math.max(6, label.scrollWidth / 24)}s`);
    requestAnimationFrame(() => track.classList.add("is-scrolling"));
  }

  function configureLocationMarquee() {
    const track = locationMarquee?.querySelector(".location-track");
    const label = track?.querySelector("strong");
    if (!track || !label) return;
    track.querySelectorAll("strong[aria-hidden='true']").forEach((copy) => copy.remove());
    track.classList.remove("is-scrolling");
    if (label.scrollWidth <= locationMarquee.clientWidth + 1) return;
    const copy = label.cloneNode(true);
    copy.setAttribute("aria-hidden", "true");
    track.append(copy);
    track.style.setProperty("--marquee-duration", `${Math.max(6, label.scrollWidth / 24)}s`);
    requestAnimationFrame(() => track.classList.add("is-scrolling"));
  }

  function applySpeaker(speaker, previousSpeaker) {
    document.querySelector("#speakerCallsign").textContent = speaker.callsign;
    document.querySelector("#speakerArea").textContent = speaker.area;
    speakerPanel.classList.remove("is-idle");
    updateCompass(speaker);
    updateMapGeometry(speaker);
    if (previousSpeaker) prependHistory(previousSpeaker);
    requestAnimationFrame(configureLocationMarquee);
  }

  function rotateSpeaker() {
    const previous = speakers[speakerIndex];
    speakerIndex = (speakerIndex + 1) % speakers.length;
    const next = speakers[speakerIndex];
    window.clearTimeout(transitionTimer);
    speakerPanel.classList.add("is-switching");
    visualStage.classList.add("is-metric-switching");
    transitionTimer = window.setTimeout(() => {
      applySpeaker(next, previous);
      speakerPanel.classList.remove("is-switching");
      visualStage.classList.remove("is-metric-switching");
    }, 190);
  }

  function pauseSpeaker() {
    speakerPanel.classList.add("is-idle");
  }

  document.addEventListener("click", (event) => {
    const viewButton = event.target.closest("[data-view]");
    if (viewButton) {
      selectView(viewButton.dataset.view);
      return;
    }

    const actionTarget = event.target.closest("[data-action]");
    if (!actionTarget) return;
    if (actionTarget.dataset.action === "toggle-tracking") {
      trackingEnabled = !trackingEnabled;
      trackingButton.classList.toggle("is-active", trackingEnabled);
      trackingButton.setAttribute("aria-pressed", String(trackingEnabled));
      trackingStatus.textContent = trackingEnabled ? "正在追踪" : "追踪已暂停";
      if (trackingEnabled) updateMapGeometry(speakers[speakerIndex]);
    } else if (actionTarget.dataset.action === "recenter") {
      trackingEnabled = true;
      trackingButton.classList.add("is-active");
      trackingButton.setAttribute("aria-pressed", "true");
      trackingStatus.textContent = "正在追踪";
      updateMapGeometry(speakers[speakerIndex]);
    } else if (actionTarget.dataset.action === "toggle-audio") {
      audioEnabled = !audioEnabled;
      window.localStorage.setItem("fmo-prototype-audio-enabled", String(audioEnabled));
      audioToggle.classList.toggle("is-active", audioEnabled);
      audioToggle.setAttribute("aria-pressed", String(audioEnabled));
      audioToggle.setAttribute("aria-label", audioEnabled ? "关闭设备声音" : "打开设备声音");
    } else if (actionTarget.dataset.action === "open-server-picker") {
      serverPicker.hidden = false;
    } else if (actionTarget.dataset.action === "close-server-picker") {
      serverPicker.hidden = true;
    } else if (actionTarget.dataset.action === "switch-server") {
      document.querySelectorAll(".server-row").forEach((row) => {
        const selected = row === actionTarget;
        row.classList.toggle("is-current", selected);
        row.querySelector("i").textContent = selected ? "✓" : "";
      });
      fullscreenServerName.textContent = actionTarget.dataset.serverName;
      document.querySelector("[data-action='open-server-picker']")?.setAttribute(
        "aria-label",
        `切换服务器，当前服务器${actionTarget.dataset.serverName}`
      );
      serverPicker.hidden = true;
      requestAnimationFrame(configureServerMarquee);
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !serverPicker.hidden) serverPicker.hidden = true;
    else if (event.key === "Escape") window.location.href = "index.html";
  });

  serverPicker.addEventListener("click", (event) => {
    if (event.target === serverPicker) serverPicker.hidden = true;
  });

  serverSearch.addEventListener("input", () => {
    const query = serverSearch.value.trim().toLocaleLowerCase();
    document.querySelectorAll(".server-row").forEach((row) => {
      row.hidden = query !== "" && !row.dataset.serverName.toLocaleLowerCase().includes(query);
    });
  });

  window.addEventListener("resize", () => {
    configureServerMarquee();
    configureLocationMarquee();
    updateMapGeometry(speakers[speakerIndex], false);
  });

  applySpeaker(speakers[0]);
  audioToggle.classList.toggle("is-active", audioEnabled);
  audioToggle.setAttribute("aria-pressed", String(audioEnabled));
  audioToggle.setAttribute("aria-label", audioEnabled ? "关闭设备声音" : "打开设备声音");
  configureServerMarquee();
  configureLocationMarquee();
  updateAudioWaveform();
  if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    window.requestAnimationFrame(animateAudioWaveform);
  }
  window.setInterval(() => {
    pauseSpeaker();
    window.setTimeout(rotateSpeaker, 1_700);
  }, 5_200);
})();
