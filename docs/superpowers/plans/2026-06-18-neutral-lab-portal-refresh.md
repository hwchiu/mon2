# Neutral Lab Portal Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `docs/` GitHub Pages 重構成中性的驗證入口網站，清楚呈現 Calico 與 Cilium 兩條驗證軌，並讓 Cilium 的真實 round 結果可直接從 HTML 頁面閱讀。

**Architecture:** 保留既有靜態 HTML 網站與 dark theme，只重做入口頁與摘要頁，再新增一頁 Cilium 結果頁。既有 Calico 詳頁不刪除，只透過新導覽與新首頁重新定位成 `Calico track` 的詳細成果頁。

**Tech Stack:** 靜態 HTML、CSS、少量原生 JavaScript、GitHub Pages (`docs/`)

---

### Task 1: 寫入 implementation plan 並確認工作範圍

**Files:**
- Create: `docs/superpowers/plans/2026-06-18-neutral-lab-portal-refresh.md`
- Reference: `docs/superpowers/specs/2026-06-18-neutral-lab-portal-design.md`

- [ ] **Step 1: 確認 spec 與 docs 範圍一致**

Run:

```bash
sed -n '1,260p' docs/superpowers/specs/2026-06-18-neutral-lab-portal-design.md
rg --files docs | sort
```

Expected:

```text
看到 spec 明確指定修改 index / experiments / install / zone-isolation / site.css，
並新增 docs/experiments/cilium-standalone-validation.html
```

- [ ] **Step 2: 提交這份 plan 文件**

Run:

```bash
git add docs/superpowers/plans/2026-06-18-neutral-lab-portal-refresh.md
git commit -m "docs: add neutral lab portal implementation plan"
```

Expected:

```text
plan 文件被提交，master 保持線性前進
```

### Task 2: 重做首頁成中性 Portal

**Files:**
- Modify: `docs/index.html`
- Modify: `docs/assets/site.css`

- [ ] **Step 1: 先讀首頁與共用樣式**

Run:

```bash
sed -n '1,260p' docs/index.html
sed -n '1,320p' docs/assets/site.css
```

Expected:

```text
確認首頁目前仍是 Calico-only 敘事，並確認現有 class 可延伸使用
```

- [ ] **Step 2: 把首頁 hero 與 summary 區改成 portal 版本**

Code to add / replace in `docs/index.html`:

```html
<div class="hero hero-portal">
  <span class="eyebrow">Lab Portal</span>
  <h1>Host Firewall Validation Lab</h1>
  <p>
    這個 repo 用同一個 Azure lab 持續驗證不同控制平面下的 host / standalone
    firewall story。網站入口先呈現兩條驗證軌，再把細節導向各自的結果頁。
  </p>
</div>
```

Expected:

```text
首頁不再把整個 repo 定義成 Calico 專屬網站
```

- [ ] **Step 3: 加入雙軌摘要卡與最新 round 區塊**

Code to add in `docs/index.html`:

```html
<section class="section" id="tracks">
  <h2>驗證軌道</h2>
  <div class="grid two track-grid">
    <article class="track-card">
      <span class="status ok">Calico Track</span>
      <h3>集中式 HostEndpoint / GlobalNetworkPolicy</h3>
      <p>既有驗證路線，重點是單一 Calico control plane 如何管理 external hosts。</p>
      <a href="./experiments/zone-isolation.html">查看 Calico 詳細結果 →</a>
    </article>
    <article class="track-card">
      <span class="status warn">Cilium Track</span>
      <h3>Cluster host policy + deprecated external workload</h3>
      <p>最新 round 已完成真實部署，結果包含 supported fail、deprecated path fail 與 Windows limitation。</p>
      <a href="./experiments/cilium-standalone-validation.html">查看 Cilium 詳細結果 →</a>
    </article>
  </div>
</section>
```

Expected:

```text
首頁能一眼看出 Calico / Cilium 兩條路線與各自入口
```

- [ ] **Step 4: 補上首頁用的 portal 樣式**

Code to add in `docs/assets/site.css`:

```css
.hero-portal {
  padding: 1.25rem 0 0.2rem;
}

.track-grid {
  align-items: stretch;
}

.track-card {
  background: linear-gradient(180deg, var(--surface), var(--surface-2));
  border: 1px solid var(--border-strong);
  border-radius: var(--radius);
  padding: 1rem 1.1rem;
}
```

Expected:

```text
新首頁區塊在既有 dark theme 上仍保持一致，不像拼裝頁
```

### Task 3: 重做實驗總覽成雙軌 Validation Board

**Files:**
- Modify: `docs/experiments.html`
- Modify: `docs/assets/site.css`

- [ ] **Step 1: 先讀既有實驗總覽**

Run:

```bash
sed -n '1,260p' docs/experiments.html
```

Expected:

```text
確認頁面目前只呈現 Calico 路線
```

- [ ] **Step 2: 改成雙軌結果看板**

Code to add / replace in `docs/experiments.html`:

```html
<section class="section">
  <h2>驗證看板</h2>
  <div class="grid two">
    <article class="card track-card">
      <span class="status ok">Calico</span>
      <h3>HostEndpoint / Zone Isolation</h3>
      <p>已完成第一輪 host zoning 驗證，結果為成功。</p>
      <a href="./experiments/zone-isolation.html">打開 Calico 結果頁 →</a>
    </article>
    <article class="card track-card">
      <span class="status warn">Cilium</span>
      <h3>Standalone Host Validation</h3>
      <p>真實部署已完成；cluster node 為 Supported fail、Linux 為 Deprecated path fail、Windows 為 limitation。</p>
      <a href="./experiments/cilium-standalone-validation.html">打開 Cilium 結果頁 →</a>
    </article>
  </div>
</section>
```

Expected:

```text
實驗頁不再偏向單一產品，且直接導向兩條詳細結果頁
```

- [ ] **Step 3: 加入 verdict badge / limitation callout 樣式**

Code to add in `docs/assets/site.css`:

```css
.badge.neutral {
  background: var(--accent-soft);
  color: var(--accent);
  border: 1px solid rgba(34, 211, 238, 0.35);
}

.callout {
  padding: 0.85rem 0.95rem;
  border-radius: var(--radius);
  border: 1px solid var(--border);
  background: var(--surface);
}

.callout.limitation {
  border-color: rgba(251, 191, 36, 0.35);
  background: rgba(251, 191, 36, 0.08);
}
```

Expected:

```text
結果分類能被快速掃描，不只靠長段落說明
```

### Task 4: 新增 Cilium HTML 結果頁

**Files:**
- Create: `docs/experiments/cilium-standalone-validation.html`
- Reference: `docs/cilium-standalone-host-validation.md`

- [ ] **Step 1: 從 markdown 擷取必要內容**

Run:

```bash
sed -n '1,260p' docs/cilium-standalone-host-validation.md
```

Expected:

```text
拿到 live validation、matrix、limitations、verdict 的原始內容
```

- [ ] **Step 2: 建立新的 Cilium 結果頁骨架**

Code to create in `docs/experiments/cilium-standalone-validation.html`:

```html
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Cilium Standalone Validation · Host Firewall Validation Lab</title>
  <link rel="stylesheet" href="../assets/site.css">
</head>
<body>
  <header class="topnav">...</header>
  <main class="shell">
    <div class="hero">
      <span class="eyebrow">Cilium Track</span>
      <h1>Cilium Standalone Host Validation</h1>
      <p>這一頁只整理真實 round 的部署結果、限制與判讀。</p>
    </div>
  </main>
</body>
</html>
```

Expected:

```text
新頁面可從瀏覽器直接打開，且使用共用樣式
```

- [ ] **Step 3: 加入三類對象 verdict 卡與測試矩陣**

Code to add in `docs/experiments/cilium-standalone-validation.html`:

```html
<section class="section">
  <h2>三類對象結果</h2>
  <div class="grid three">
    <article class="card">
      <span class="badge warn">Supported fail</span>
      <h3>Kubernetes nodes</h3>
      <p>zone1 allow 成功，但 cross-zone deny 仍放行。</p>
    </article>
    <article class="card">
      <span class="badge warn">Deprecated path fail</span>
      <h3>Linux standalone VM</h3>
      <p>deprecated external workload attached，但 VM 本地沒有載入 policy。</p>
    </article>
    <article class="card">
      <span class="badge neutral">Windows limitation</span>
      <h3>Windows standalone VM</h3>
      <p>VM 與 IIS 正常，但沒有建立官方支援的 standalone Cilium-managed attachment path。</p>
    </article>
  </div>
</section>
```

Expected:

```text
訪客不看 markdown 也能讀懂這次 round 的核心結論
```

- [ ] **Step 4: 加入限制說明與原始文件連結**

Code to add in `docs/experiments/cilium-standalone-validation.html`:

```html
<section class="section">
  <h2>限制與判讀</h2>
  <div class="callout limitation">
    Windows 的結論不是 lab/config error，而是 `No official standalone Windows path found`。
  </div>
  <p><a href="../cilium-standalone-host-validation.md">閱讀原始 markdown 記錄 →</a></p>
</section>
```

Expected:

```text
Cilium 頁能清楚區分產品限制與實驗失敗
```

### Task 5: 統一品牌與導覽文字

**Files:**
- Modify: `docs/index.html`
- Modify: `docs/experiments.html`
- Modify: `docs/install.html`
- Modify: `docs/experiments/zone-isolation.html`

- [ ] **Step 1: 把品牌名稱改成中性 portal**

Run:

```bash
rg -n "Calico Central Firewall Lab" docs/index.html docs/experiments.html docs/install.html docs/experiments/zone-isolation.html
```

Expected before edit:

```text
四個頁面都仍帶有舊品牌
```

- [ ] **Step 2: 把品牌與導覽文案更新為中性版本**

Replacement target:

```html
<a class="brand" href="../index.html">Host Firewall Validation Lab</a>
```

Expected:

```text
主導航與品牌名稱不再把整個網站定義成 Calico-only
```

### Task 6: 驗證、提交、推送

**Files:**
- Verify: `docs/index.html`
- Verify: `docs/experiments.html`
- Verify: `docs/install.html`
- Verify: `docs/experiments/zone-isolation.html`
- Verify: `docs/experiments/cilium-standalone-validation.html`
- Verify: `docs/assets/site.css`

- [ ] **Step 1: 檢查 diff 與基本一致性**

Run:

```bash
git diff --check
git diff -- docs/index.html docs/experiments.html docs/install.html docs/experiments/zone-isolation.html docs/experiments/cilium-standalone-validation.html docs/assets/site.css
```

Expected:

```text
沒有 whitespace error，且所有改動都集中在 portal 重構範圍
```

- [ ] **Step 2: 用搜尋驗證首頁敘事與新頁入口**

Run:

```bash
rg -n "Cilium Track|Calico Track|Host Firewall Validation Lab|Windows limitation" docs/index.html docs/experiments.html docs/experiments/cilium-standalone-validation.html
```

Expected:

```text
首頁、看板頁、Cilium 詳頁都能找到對應關鍵字
```

- [ ] **Step 3: 提交網站更新**

Run:

```bash
git add docs/index.html docs/experiments.html docs/install.html docs/experiments/zone-isolation.html docs/experiments/cilium-standalone-validation.html docs/assets/site.css docs/superpowers/plans/2026-06-18-neutral-lab-portal-refresh.md
git commit -m "docs: refresh github pages lab portal"
```

Expected:

```text
網站與 plan 一起提交，master 保持乾淨
```

- [ ] **Step 4: push 到 GitHub**

Run:

```bash
git push origin master
```

Expected:

```text
origin/master 更新成功，GitHub Pages 可開始發布新版 docs
```
