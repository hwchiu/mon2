# Neutral Lab Portal Design

## Goal

把目前偏向 Calico 單一路線的 GitHub Pages 網站，重構成一個**中性的 Lab Portal**，讓讀者一打開首頁就能理解：

- 這個 repo 驗證的是什麼
- 目前有哪兩條驗證路線
- Calico 與 Cilium 各自驗證到哪裡
- 哪些結果是成功、哪些是限制、哪些是失敗

網站主要閱讀語言改為**繁體中文**，但保留技術名詞、檔名、badge、verdict 名稱的英文原文。

## Current Problem

目前 `docs/` 網站入口仍然把整個 repo 包裝成 `Calico Central Firewall Lab`：

- [docs/index.html](/home/ubuntu/mon2/docs/index.html:1) 首頁只講 Calico 架構
- [docs/experiments.html](/home/ubuntu/mon2/docs/experiments.html:1) 只呈現 Calico 實驗看板
- Cilium 已經有完整 markdown 驗證文件，但沒有被整理成好讀的 HTML 結果頁
- GitHub Pages 訪客會誤判 repo 的主題仍是 Calico-only，而不是多路線的 host / cluster firewall validation lab

這不是內容不足，而是**資訊架構與首頁敘事錯位**。

## User-Facing Outcome

重構後的網站應該讓讀者在 30 秒內看懂：

1. 這個 repo 是一個 Lab Portal，不是單一產品展示頁。
2. Repo 目前至少有兩條明確驗證軌：
   - `Calico`
   - `Cilium`
3. 每條驗證軌都有：
   - 驗證目的
   - 控制平面來源
   - 涵蓋對象
   - 最新 round 結果
   - 主要限制或下一步
4. `Cilium` 這次真實部署結果會直接出現在 HTML 頁面，不再只能從 markdown 原文讀出。

## Information Architecture

網站改成以下結構：

### 1. Home / Portal

入口頁改成中性 Lab Portal：

- 中性品牌名稱
- 站點目的摘要
- 兩條驗證軌的摘要卡
- 最新 round / 重要限制 / 支援文件入口

首頁先講「結論與分類」，再導流到細節頁。

### 2. Experiments / Validation Board

實驗總覽頁改成驗證看板，不再只寫某一條路線的進度。頁面分成兩大區塊：

- `Calico 驗證軌`
- `Cilium 驗證軌`

每個區塊都固定有：

- 背景與目的
- 涵蓋環境
- 最新結果
- 下一步或限制
- 細節頁入口

### 3. Calico Detail

既有 Calico 詳頁保留，不推翻現有內容。其角色改成：

- 既有驗證成果頁
- 從首頁與看板以「Calico track」方式導入

### 4. Cilium Detail

新增獨立 HTML 詳頁，專門呈現這次真實部署的 Cilium standalone validation：

- 測試目標
- 實際環境
- 三類對象結果
  - Kubernetes nodes
  - Linux standalone VM
  - Windows standalone VM
- 測試矩陣
- 關鍵限制
- 延伸閱讀（回到 markdown 設計 / runbook / scripts）

### 5. Support Docs

`Install Guide`、原始 markdown 文件、runbook 留在網站中，但從首頁降成支援文件，不再承擔主敘事。

## Content Model

所有摘要頁面應使用同一套分類語彙，避免不同頁面各說各話：

- `Supported pass`
- `Supported fail`
- `Deprecated path pass`
- `Deprecated path fail`
- `No official standalone Windows path found`
- `Attempted path incompatible with Windows`
- `Lab/config error`
- `Unclear / needs more evidence`

首頁與看板頁不需要列出全部 taxonomy，但至少要清楚區分三種判讀：

- 成功
- 產品限制
- 實驗失敗 / 尚未驗證

其中 Cilium 頁面要明確呈現這次真實 round 的實際分類：

- Kubernetes nodes: `Supported fail`
- Linux standalone VM: `Deprecated path fail`
- Windows standalone VM: `No official standalone Windows path found`

## Visual Direction

不重做整套設計系統，只在現有 dark theme 基礎上重組版面與元件。

原則：

- 保留現有深色技術文件風格
- 品牌名稱改為中性，不綁 Calico
- 把重點從「架構圖先行」改成「摘要先行」
- 增加適合驗證 portal 的元件：
  - track card
  - result badge
  - limitation callout
  - summary stats

語氣維持工程文件風格：

- 直接
- 可掃讀
- 不包裝失敗
- 清楚標示限制與證據

## File Changes

### Modify

- `docs/index.html`
  - 改為中性首頁 portal
- `docs/experiments.html`
  - 改為雙軌 validation board
- `docs/install.html`
  - 更新品牌與導覽文字，避免仍寫成 Calico-only
- `docs/experiments/zone-isolation.html`
  - 更新導覽與品牌敘事，讓它被定位成 Calico track 的既有成果頁
- `docs/assets/site.css`
  - 補上 portal / track / badge / callout 樣式

### Create

- `docs/experiments/cilium-standalone-validation.html`
  - 這次真實 Cilium 驗證的 HTML 結果頁

## Navigation

主導航維持簡單三段：

- `總覽`
- `驗證看板`
- `安裝與支援`

但品牌名稱改為中性，例如：

- `Host Firewall Validation Lab`

首頁與看板都要能一鍵導到：

- Calico 詳頁
- Cilium 詳頁
- 安裝頁

## Verification Strategy

不引入前端 build system。直接驗證靜態 HTML：

1. 檢查所有頁面互相連結是否正確
2. 檢查首頁是否不再出現 Calico-only 主敘事
3. 檢查實驗總覽頁是否同時呈現 Calico / Cilium
4. 檢查新的 Cilium HTML 頁是否完整呈現真實 round 結果
5. 檢查 CSS 調整沒有讓既有頁面失去可讀性
6. 提交到 `master` 並 push 到 `origin/master`

## Non-Goals

這次不做：

- 重寫既有 Calico 詳細技術內容
- 新增 JS framework 或 site generator
- 重新設計所有 SVG
- 修改 GitHub Pages 發布機制
- 補做新的 Cilium 測試結果

## Risks

### Risk 1: 首頁改太大，舊頁敘事斷裂

處理方式：

- 保留既有 Calico 詳頁
- 只重做入口與摘要頁
- 用一致導覽把舊頁重新掛回 portal

### Risk 2: Cilium 結果寫太多細節，首頁變難讀

處理方式：

- 首頁只保留 verdict 與短摘要
- 細節全部下放到 Cilium 專頁

### Risk 3: 現有 CSS 無法支撐新的 portal 區塊

處理方式：

- 以增量 class 為主
- 不大幅推翻既有排版與色彩 token

## Success Criteria

完成後應滿足：

1. GitHub Pages 首頁明確是中性 portal，而不是 Calico-only 首頁
2. `Calico` 與 `Cilium` 兩條驗證軌都能直接被看見
3. Cilium 的真實結果可以在 HTML 頁面中直接閱讀
4. Windows limitation 被清楚分類，不混成 lab error
5. 整個網站的繁體中文敘事一致、容易掃描、沒有互相矛盾
