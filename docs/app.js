// AgentBadges frontend — static, no backend, no keys.
// All reads go through the public BSC RPC below; writes go through the
// user's own injected wallet (Binance Wallet / MetaMask).
// ---------------------------------------------------------------------------
// TODO AFTER DEPLOY: set CONTRACT_ADDRESS to the deployed contract and
// DEPLOY_BLOCK to the block number of the deployment transaction.
// ---------------------------------------------------------------------------
const CONFIG = {
  CONTRACT_ADDRESS: "0x0000000000000000000000000000000000000000", // TODO
  DEPLOY_BLOCK: 0, // TODO
  AGENT_ID_ADDRESS: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F",
  CHAIN_ID: 56, // BSC mainnet
  RPC_URL: "https://bsc-dataseed.binance.org/",
};

const BADGES = [
  { id: 1, name: "First GM", desc: "Say GM once as an Agent ID holder.", req: "GM at least once" },
  { id: 2, name: "Three-Day Streak", desc: "Say GM on 3 consecutive days.", req: "3-day GM streak" },
  { id: 3, name: "Seven-Day Streak", desc: "Say GM on 7 consecutive days.", req: "7-day GM streak" },
  { id: 4, name: "First Tip", desc: "Tip another Agent ID holder at least 0.0001 BNB.", req: "Tip someone once" },
  { id: 5, name: "Collector", desc: "Hold any 3 AgentBadges.", req: "Own 3 badges" },
];

const ABI = [
  "function gm()",
  "function tip(address to) payable",
  "function claimBadge(uint256 badgeId)",
  "function badgesOf(address user) view returns (uint256[])",
  "function gmStreak(address user) view returns (uint256)",
  "function totalGmDays(address user) view returns (uint256)",
  "function lastGmDay(address user) view returns (uint256)",
  "function hasTipped(address user) view returns (bool)",
  "function badgeCount(address user) view returns (uint256)",
  "function hasBadge(address user, uint256 badgeId) view returns (bool)",
  "function isAgentIdHolder(address user) view returns (bool)",
  "function balanceOf(address owner) view returns (uint256)",
  "function tokenURI(uint256 tokenId) view returns (string)",
  "event GM(address indexed user, uint256 indexed day, uint256 streak)",
  "event Tip(address indexed from, address indexed to, uint256 amount)",
  "event BadgeClaimed(address indexed user, uint256 indexed badgeId, uint256 tokenId)",
];

const AGENT_ID_ABI = [
  "function balanceOf(address owner) view returns (uint256)",
  "function tokenURI(uint256 tokenId) view returns (string)",
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
];

const $ = (id) => document.getElementById(id);
const short = (a) => (a ? a.slice(0, 6) + "…" + a.slice(-4) : "—");

let readProvider, agentId, badges, signer, signerAddress = null, userState = null;

function isDeployed() {
  return CONFIG.CONTRACT_ADDRESS && CONFIG.CONTRACT_ADDRESS !== "0x0000000000000000000000000000000000000000";
}

async function withTimeout(promise, ms, label) {
  const timer = new Promise((_, rej) => setTimeout(() => rej(new Error(label + " timed out")), ms));
  return Promise.race([promise, timer]);
}

// Resolve an Agent ID name (e.g. "ainggm.ai") for an address.
// Primary: the Agent ID mint Transfer event gives the tokenId, then tokenURI
// metadata carries the name. Falls back to the truncated address on any error.
// (The Agent ID contract has no ERC721Enumerable, so enumeration is impossible.)
async function resolveAgentName(address) {
  try {
    const topic0 = ethers.id("Transfer(address,address,uint256)");
    const topicTo = "0x000000000000000000000000" + address.slice(2).toLowerCase();
    const logs = await withTimeout(
      readProvider.getLogs({ address: CONFIG.AGENT_ID_ADDRESS, topics: [topic0, null, topicTo], fromBlock: 0, toBlock: "latest" }),
      15000, "name lookup"
    );
    if (!logs.length) return short(address);
    const tokenId = BigInt(logs[logs.length - 1].topics[3]);
    const uri = await withTimeout(agentId.tokenURI(tokenId), 8000, "tokenURI");
    const url = uri.startsWith("ipfs://") ? "https://ipfs.io/ipfs/" + uri.slice(7) : uri;
    const res = await withTimeout(fetch(url), 8000, "metadata fetch");
    const meta = await res.json();
    return meta.name || short(address);
  } catch (e) {
    return short(address);
  }
}

async function refreshUser() {
  if (!signerAddress) return;
  const [holder, streak, gmDays, count, tipped] = await Promise.all([
    badges.isAgentIdHolder(signerAddress),
    badges.gmStreak(signerAddress),
    badges.totalGmDays(signerAddress),
    badges.badgeCount(signerAddress),
    badges.hasTipped(signerAddress),
  ]);
  const owned = await badges.badgesOf(signerAddress);
  userState = { holder, streak: Number(streak), gmDays: Number(gmDays), count: Number(count), tipped, owned: owned.map(Number) };
  $("holder").textContent = holder ? "Yes" : "No";
  $("holder").className = "value " + (holder ? "ok" : "error");
  $("streak").textContent = userState.streak;
  $("gmDays").textContent = userState.gmDays;
  $("badgeCount").textContent = userState.count + " / 5";
  $("agentName").textContent = await resolveAgentName(signerAddress);
  renderBadges();
  updateActionButtons();
}

function eligible(badgeId) {
  if (!userState || !userState.holder) return false;
  if (badgeId === 1) return userState.gmDays >= 1;
  if (badgeId === 2) return userState.streak >= 3;
  if (badgeId === 3) return userState.streak >= 7;
  if (badgeId === 4) return userState.tipped;
  if (badgeId === 5) return userState.count >= 3;
  return false;
}

function renderBadges() {
  const grid = $("badgeGrid");
  grid.innerHTML = "";
  for (const b of BADGES) {
    const owned = userState ? userState.owned.includes(b.id) : false;
    const canClaim = !owned && eligible(b.id);
    const div = document.createElement("div");
    div.className = "badge" + (owned ? " earned" : "");
    div.innerHTML = `
      <img src="badges/${b.id}.svg" alt="${b.name}">
      <h3>${b.name}</h3>
      <p class="req">${b.desc}<br>Requires: ${b.req}</p>
      <div class="status ${owned ? "earned" : "locked"}">${owned ? "Earned" : canClaim ? "Ready to claim" : "Locked"}</div>`;
    const btn = document.createElement("button");
    btn.textContent = owned ? "Claimed" : "Claim Badge";
    btn.disabled = !canClaim;
    btn.onclick = () => claimBadge(b.id, btn);
    div.appendChild(btn);
    grid.appendChild(div);
  }
}

function updateActionButtons() {
  const ok = !!signerAddress && isDeployed() && userState && userState.holder;
  $("gmBtn").disabled = !ok;
  $("tipBtn").disabled = !ok;
  $("gmNote").textContent = !signerAddress ? "Connect your wallet first." :
    !isDeployed() ? "Contract not deployed yet." :
    !userState.holder ? "This wallet does not hold an Agent ID." : "";
}

async function claimBadge(badgeId, btn) {
  try {
    btn.disabled = true; btn.textContent = "Claiming…";
    const tx = await badges.connect(signer).claimBadge(badgeId);
    await tx.wait();
    await refreshUser();
  } catch (e) {
    alert("Claim failed: " + (e.reason || e.message || e));
    btn.disabled = false; btn.textContent = "Claim Badge";
  }
}

async function loadLeaderboard() {
  const status = $("lbStatus");
  if (!isDeployed()) { status.textContent = "Leaderboard appears after the contract is deployed."; return; }
  try {
    const latest = await readProvider.getBlockNumber();
    const from = CONFIG.DEPLOY_BLOCK || 0;
    const iface = new ethers.Interface(ABI);
    const gmTopic = iface.getEvent("GM").topicHash;
    const claimTopic = iface.getEvent("BadgeClaimed").topicHash;
    const CHUNK = 5000;
    const users = {}; // addr -> { bestStreak, gmDays, badges }
    const bump = (a) => (users[a] = users[a] || { bestStreak: 0, gmDays: 0, badges: 0 });
    for (let start = from; start <= latest; start += CHUNK) {
      const end = Math.min(start + CHUNK - 1, latest);
      const logs = await readProvider.getLogs({ address: CONFIG.CONTRACT_ADDRESS, topics: [[gmTopic, claimTopic]], fromBlock: start, toBlock: end });
      for (const log of logs) {
        const parsed = iface.parseLog(log);
        const u = bump(parsed.args.user.toLowerCase());
        if (parsed.name === "GM") {
          u.gmDays += 1;
          u.bestStreak = Math.max(u.bestStreak, Number(parsed.args.streak));
        } else if (parsed.name === "BadgeClaimed") {
          u.badges += 1;
        }
      }
      status.textContent = `Loading on-chain activity… (blocks ${start.toLocaleString()}–${end.toLocaleString()} of ${latest.toLocaleString()})`;
    }
    const addrs = Object.keys(users);
    const byStreak = [...addrs].sort((a, b) => users[b].bestStreak - users[a].bestStreak || users[b].gmDays - users[a].gmDays).slice(0, 10);
    const byBadges = [...addrs].sort((a, b) => users[b].badges - users[a].badges || users[b].bestStreak - users[a].bestStreak).slice(0, 10);
    const fill = async (tbodyId, list, cols) => {
      const tbody = $(tbodyId); tbody.innerHTML = "";
      if (!list.length) { tbody.innerHTML = `<tr><td colspan="4">No activity yet — be the first to GM.</td></tr>`; return; }
      for (let i = 0; i < list.length; i++) {
        const a = list[i], u = users[a];
        const name = await resolveAgentName(a);
        const tr = document.createElement("tr");
        tr.innerHTML = `<td>${i + 1}</td><td title="${a}">${name}</td>` + cols(u);
        tbody.appendChild(tr);
      }
    };
    await fill("lbStreak", byStreak, (u) => `<td>${u.bestStreak}</td><td>${u.gmDays}</td>`);
    await fill("lbBadges", byBadges, (u) => `<td>${u.badges} / 5</td>`);
    status.textContent = addrs.length ? `${addrs.length} agent(s) on the board.` : "No activity yet — be the first to GM.";
  } catch (e) {
    status.textContent = "Leaderboard could not load (public RPC slow or unreachable). Try refreshing the page.";
  }
}

async function connect() {
  const btn = $("connectBtn");
  try {
    if (!window.ethereum) { alert("No wallet found. Install Binance Wallet or MetaMask, then refresh."); return; }
    const provider = new ethers.BrowserProvider(window.ethereum);
    const network = await provider.getNetwork();
    if (Number(network.chainId) !== CONFIG.CHAIN_ID) {
      try {
        await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: "0x38" }] });
      } catch (e) {
        if (e.code === 4902) {
          await window.ethereum.request({ method: "wallet_addEthereumChain", params: [{ chainId: "0x38", chainName: "BNB Smart Chain", nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 }, rpcUrls: ["https://bsc-dataseed.binance.org/"], blockExplorerUrls: ["https://bscscan.com/"] }] });
        } else { throw e; }
      }
    }
    signer = await provider.getSigner();
    signerAddress = await signer.getAddress();
    badges = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, ABI, provider);
    $("connectBtn").textContent = short(signerAddress);
    $("addr").textContent = short(signerAddress);
    $("chainNote").textContent = "Connected to BNB Smart Chain (chain 56).";
    await refreshUser();
  } catch (e) {
    alert("Connect failed: " + (e.reason || e.message || e));
  }
}

$("connectBtn").onclick = connect;
$("gmBtn").onclick = async () => {
  try {
    $("gmBtn").disabled = true; $("gmBtn").textContent = "GMing…";
    const tx = await badges.connect(signer).gm();
    await tx.wait();
    $("gmNote").textContent = "GM recorded. See you tomorrow for the next one.";
    await refreshUser();
  } catch (e) {
    alert("GM failed: " + (e.reason || e.message || e));
  } finally {
    $("gmBtn").disabled = false; $("gmBtn").textContent = "Say GM";
  }
};
$("tipBtn").onclick = async () => {
  try {
    const to = $("tipTo").value.trim();
    const amount = $("tipAmount").value;
    if (!ethers.isAddress(to)) { alert("Enter a valid recipient address."); return; }
    if (Number(amount) < 0.0001) { alert("Minimum tip is 0.0001 BNB."); return; }
    $("tipBtn").disabled = true; $("tipBtn").textContent = "Sending…";
    const tx = await badges.connect(signer).tip(to, { value: ethers.parseEther(amount) });
    await tx.wait();
    $("tipNote").textContent = "Tip sent. First Tip badge is ready to claim.";
    await refreshUser();
  } catch (e) {
    alert("Tip failed: " + (e.reason || e.message || e));
  } finally {
    $("tipBtn").disabled = false; $("tipBtn").textContent = "Send Tip";
  }
};

(async function init() {
  readProvider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
  agentId = new ethers.Contract(CONFIG.AGENT_ID_ADDRESS, AGENT_ID_ABI, readProvider);
  if (isDeployed()) {
    badges = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, ABI, readProvider);
    $("contractAddr").innerHTML = `<a href="https://bscscan.com/address/${CONFIG.CONTRACT_ADDRESS}" target="_blank" rel="noopener">${CONFIG.CONTRACT_ADDRESS}</a>`;
  } else {
    $("deployBanner").style.display = "block";
  }
  renderBadges();
  updateActionButtons();
  loadLeaderboard();
  if (window.ethereum) {
    window.ethereum.on("accountsChanged", () => location.reload());
    window.ethereum.on("chainChanged", () => location.reload());
  }
})();
