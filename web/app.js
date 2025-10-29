(() => {
  const RES = GetParentResourceName();
  const root = document.getElementById('root');
  const shopLabel = document.getElementById('shopLabel');
  const catsDiv = document.getElementById('cats');
  const vehList = document.getElementById('vehList');
  const panel = document.getElementById('vehPanel');
  const closeBtn = document.getElementById('closeBtn');
  const sidePanel     = document.getElementById('detail');
  const panelCloseBtn = document.getElementById('panelClose'); 
  const peekX = document.getElementById('peekX');
  const viewCatalog = document.getElementById('view-catalogue');
  const viewCounter = document.getElementById('view-counter');
  const viewBoss    = document.getElementById('view-boss');
  const closeCounter= document.getElementById('closeCounter');
  const closeBoss   = document.getElementById('closeBoss');
  const secReception = document.getElementById('sec-reception');
  const secLogs      = document.getElementById('sec-logs');
  const stockInfo  = document.getElementById('stockInfo');
  const stockList  = document.getElementById('stockList');
  const stockCat   = document.getElementById('stockCat');
  const stockSearch= document.getElementById('stockSearch');
  let   stockRows  = [];
  let logiRows = [];
  let logiRowsFiltered = [];
  const logiInfo  = document.getElementById('logiInfo');
  const logiList  = document.getElementById('logiList');
  const logiCat   = document.getElementById('logiCat');
  const logiSearch= document.getElementById('logiSearch');


  let counterSection = 'spots'; // 'spots' | 'logi' | 'logs'

function openModal(){              
  sidePanel.classList.remove('hidden');
  document.body.classList.add('has-detail');
  panel.classList.remove('hidden');
}
function closeModal(){             
  sidePanel.classList.add('hidden');
  document.body.classList.remove('has-detail');
  panel.innerHTML = '';
  panel.classList.remove('hidden');
}
panelCloseBtn.addEventListener('click', closeModal);

function enterPeek(){
  state.peek = true;
  hideRoot();                      // masque le catalogue seulement
  peekX.classList.remove('hidden'); // affiche la grosse croix
}

function exitPeek(){
  state.peek = false;
  showRoot();                      // ré-affiche le catalogue
  peekX.classList.add('hidden');
}
peekX.addEventListener('click', exitPeek);


let state = {
    shop: null,
    categories: [],
    currentCat: null,
    currentVeh: null,
    isDealer: false,
    primary: '#000000',
    secondary: '#000000',
    pay: 'bank',
    dealersOnline: 0,         // ⬅️ ajouté
    autoBuyAllowed: true,      // ⬅️ ajouté (true=aucun vendeur en ville)
    peek: false
  };

  function nui(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: JSON.stringify(data)
    }).then(r => r.json().catch(() => ({})));
  }

  function showRoot() { root.classList.remove('hidden'); }
  function hideRoot() { root.classList.add('hidden');}
  function hide(el){ el.classList.add('hidden'); }
  function show(el){ el.classList.remove('hidden'); }

  window.addEventListener('message', async (e) => {
    const msg = e.data || {};
    if (msg.action === 'open') {
      shopLabel.textContent = msg.shop?.label || 'Concession';
      state.shop = msg.shop || null;
      state.isDealer = !!(msg.shop?.isDealer);
      state.dealersOnline = Number(msg.shop?.dealersOnline ?? 0);
      state.autoBuyAllowed = state.dealersOnline === 0; // acheter dispo seulement si 0 vendeur
      buildCategories(msg.categories || []);
      showView('catalog');
    } else if (msg.action === 'close') {
      hideRoot();
      vehList.innerHTML = '';
      panel.innerHTML = '';
    }
    else if (msg.action === 'hide') {
      enterPeek();
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape'){
      if (!sidePanel.classList.contains('hidden')) return closeModal(); // ✅
      if (state.peek) return exitPeek();
      nui('ui:close');
    }
  });

  async function stockLoad(){
  const d = await nui('stock:getList', { shopId: state.shop?.id });   // (callback client -> serveur ci-dessous)
  stockRows = d.rows || [];
  const cats = [...new Set(stockRows.map(r => r.category || ''))].filter(Boolean).sort();
  stockCat.innerHTML = `<option value="">Toutes catégories</option>` + cats.map(c=>`<option value="${c}">${c}</option>`).join('');
  stockInfo.textContent = `Articles: ${stockRows.length.toLocaleString()}`;
  renderStock();
}
// === helpers popups très légers ===
function quickPopup({ title = '', askColor = false, askPay = false, defaultColor = '#000000' } = {}) {
  return new Promise((resolve) => {
    const wrap = document.createElement('div');
    wrap.className = 'quickpop';
    wrap.innerHTML = `
      <div class="quickpop__bg"></div>
      <div class="quickpop__win">
        <div class="quickpop__title">${title}</div>
        <div class="quickpop__body">
          ${askColor ? `
            <label class="qp_row">
              <span>Couleur</span>
              <input type="color" id="qp_color" value="${defaultColor}">
            </label>
          ` : ``}
          ${askPay ? `
            <label class="qp_row">
              <span>Mode de paiement</span>
              <select id="qp_pay" class="input">
                <option value="bank">Banque</option>
                <option value="money">Espèces</option>
              </select>
            </label>
          ` : ``}
        </div>
        <div class="quickpop__actions">
          <button class="btn btn-ghost" id="qp_cancel">Annuler</button>
          <button class="btn btn-blue" id="qp_ok">Valider</button>
        </div>
      </div>
    `;

    document.body.appendChild(wrap);

    const done = (val) => { wrap.remove(); resolve(val); };
    wrap.querySelector('#qp_cancel').onclick = () => done(null);
    wrap.querySelector('#qp_ok').onclick = () => {
      const color = askColor ? (wrap.querySelector('#qp_color').value || defaultColor) : undefined;
      const pay   = askPay   ? (wrap.querySelector('#qp_pay').value || 'bank')       : undefined;
      done({ color, pay });
    };
    wrap.querySelector('.quickpop__bg').onclick = () => done(null);
  });
}


function receptionLoad() {
  if (typeof logiLoad === 'function') return logiLoad();
  console.warn('logiLoad() est introuvable');
}

// === LISTE DU STOCK (2 boutons : facture / moi) ===
function renderStock(){
  if (!stockList) return;

  const q   = (stockSearch.value||'').toLowerCase().trim();
  const cat = stockCat.value || '';

  stockList.innerHTML = '';

  stockRows
    .filter(r => {
      if (cat && r.category !== cat) return false;
      if (q){
        const blob = `${r.name||''} ${r.model||''} ${r.category||''}`.toLowerCase();
        if (!blob.includes(q)) return false;
      }
      return true;
    })
    .forEach(r => {
      const stockNum = Number(r.stock || 0);
      const hasStock = stockNum > 0;

      const el = document.createElement('div');
      el.className = 'rowItem';
      el.innerHTML = `
        <div class="thumb">${r.image ? `<img src="${r.image}" alt="">` : `<span class="small">IMG</span>`}</div>
        <div>
          <div class="title">${r.name || r.model} <span class="sub">| ${Number(r.price||0).toLocaleString()} $</span></div>
          <div class="sub">Stock: ${stockNum} • Cat: ${r.category||'-'}</div>
        </div>
        <div class="actions">
          ${hasStock ? `
            <button class="iconBtn" title="Facture au client" data-act="bill">🧾</button>
            <button class="iconBtn" title="Me vendre"          data-act="self">👤</button>
          ` : `
            <span class="outStock">Besoin de réapprovisionnement</span>
          `}
        </div>
      `;

      if (hasStock) {
        el.querySelectorAll('.iconBtn').forEach(btn => {
          btn.addEventListener('click', async () => {
            const act = btn.getAttribute('data-act');

            if (act === 'bill') {
              const res = await nui('stock:bill', {
                model: r.model,
                name:  r.name,
                price: r.price
              });
              if (!res?.ok) {
                toast(res?.msg || 'Erreur envoi facture', false);
              } else {
                await nui('ui:close');
                toast('Facture ouverte (remplissez-la)', true);
              }
              return;
            }

            if (act === 'self') {
              const pick = await quickPopup({ title:'Acheter pour moi', askColor:true, askPay:true, defaultColor:'#000000' });
              if (!pick) return;

              const res = await nui('ui:buyAsDealer', {
                customerType:'moi',
                model:r.model, name:r.name, price:r.price,
                color: pick.color, pay: pick.pay
              });
              await nui('ui:close');
              if (!res?.ok) toast('Achat: une erreur est survenue.', false);
            }
          });
        });
      }

      stockList.appendChild(el);
    });
}

stockSearch?.addEventListener('input', renderStock);
stockCat?.addEventListener('change', renderStock);


  function showView(v){
    // cache tout
    document.getElementById('root').classList.remove('hidden');
    viewCatalog.classList.add('hidden');
    viewCounter.classList.add('hidden');
    viewBoss.classList.add('hidden');
    // ta vue catalogue est déjà dans la page; on la laisse telle quelle
    if (v === 'catalog') viewCatalog.classList.remove('hidden');
    if (v==='counter') viewCounter.classList.remove('hidden');
    if (v==='boss')    viewBoss.classList.remove('hidden');

    document.getElementById('root').classList.remove('hidden');
  }

  window.addEventListener('message', async (e) => {
    const msg = e.data || {};
    if (msg.action === 'stock:paid'){  // {model,name,price,pay,targetId}
      await nui('ui:buyAsDealer', {
        customerType:'particulier', targetId: msg.targetId,
        model: msg.model, name: msg.name, price: msg.price, color:'#000000', pay: msg.pay||'bank'
      });
    }
    if (msg.action === 'openCounter') {
      showView('counter');
      counterSection = msg.startSection || 'spots';
      await counterLoad();
    } else if (msg.action === 'openBoss') {
      showView('boss');
      await bossLoad();
      await reloadBossEmployees()
    }
    // (tes handlers 'open', 'close', 'hide' catalogue restent)
  });
  closeCounter.addEventListener('click', () => nui('ui:close'));
  closeBoss.addEventListener('click', () => nui('ui:close'));

  // ======= Comptoir =======
  let counterSpots  = [];
  let counterFilter = 'all';
  let counterSearch = '';

  const chipsWrap   = document.getElementById('chipsFilter');
  const inputSearch = document.getElementById('spotGlobalSearch');
  const btnAnnPromo = document.getElementById('btnAnnPromo');

  async function histReload(){
    const r = await nui('counter:getHistory', {});
    const rows = (r && r.history) || [];
    const tb = document.querySelector('#histTable tbody');
    if (!tb) return;
    tb.innerHTML = '';
    rows.forEach(row=>{
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td style="padding:6px">${row.date||''}</td>
        <td style="padding:6px">${row.type||''}</td>
        <td style="padding:6px">${row.vehicle||''}</td>
        <td style="padding:6px;text-align:right">${row.gain||'/'}</td>
        <td style="padding:6px;text-align:right">${row.cost||'/'}</td>
        <td style="padding:6px;text-align:right">
          <button class="btn btn-ghost" data-id="${row.id}">Suppr.</button>
        </td>`;
      tr.querySelector('button').addEventListener('click', async()=>{
        await nui('counter:deleteHistory', { id: row.id });
        histReload();
      });
      tb.appendChild(tr);
    });
  }
  document.getElementById('btnHistReload')?.addEventListener('click', histReload);


  const sectionsWrap = document.getElementById('counterSections');
  sectionsWrap?.addEventListener('click', (e)=>{
    const sec = e.target && e.target.getAttribute('data-sec');
    if (!sec) return;
    counterSection = sec;
    // toggle vues
    document.getElementById('sec-spots').classList.toggle('hidden', sec!=='spots');
    document.getElementById('sec-logi').classList.toggle('hidden',  sec!=='logi');   
    document.getElementById('sec-logs').classList.toggle('hidden',  sec!=='logs');
    if (sec === 'logi') stockLoad();
    if (sec === 'logs') histReload();
  });


  if (btnAnnPromo) {
    btnAnnPromo.addEventListener('click', () => {
      const txt = prompt('Texte annonce promo :','Promo exceptionnelle chez le concessionnaire !');
      if (txt && txt.trim()) nui('counter:announce', {type:'custom', text: txt.trim()});
    });
  }

  if (chipsWrap) {
    chipsWrap.addEventListener('click', (e)=>{
      const f = e.target && e.target.getAttribute('data-filter');
      if (!f) return;
      counterFilter = f;
      chipsWrap.querySelectorAll('.btn-ghost').forEach(b => b.removeAttribute('data-active'));
      e.target.setAttribute('data-active','1');
      renderSpots();
    });
  }

  if (inputSearch) {
    inputSearch.addEventListener('input', ()=>{
      counterSearch = (inputSearch.value||'').toLowerCase().trim();
      renderSpots();
    });
  }
  
  async function counterLoad(){
    const d = await nui('counter:getData', {});
    const balEl = document.getElementById('counterBalance');
    if (balEl) balEl.textContent = `Solde: ${Number(d.balance||0).toLocaleString()} $`;

    await loadSpots();

    document.getElementById('sec-spots').classList.toggle('hidden', counterSection!=='spots');
    document.getElementById('sec-logi').classList.toggle('hidden',  counterSection!=='logi');
    document.getElementById('sec-logs').classList.toggle('hidden',  counterSection!=='logs');

    if (counterSection === 'logi') await logiLoad();
    if (counterSection === 'logs') await histReload();
  }



  document.getElementById('btnDeposit').addEventListener('click', async () => {
    const amount = Number(document.getElementById('counterAmount').value||0);
    if (amount>0){ await nui('counter:deposit', {amount}); counterLoad(); }
  });

  document.getElementById('btnWithdraw').addEventListener('click', async () => {
    const amount = Number(document.getElementById('counterAmount').value||0);
    if (amount>0){ await nui('counter:withdraw', {amount}); counterLoad(); }
  });

  document.getElementById('btnAnnOpen').addEventListener('click', () => nui('counter:announce', {type:'open'}));
  document.getElementById('btnAnnClose').addEventListener('click', () => nui('counter:announce', {type:'close'}));
  document.getElementById('btnAnnCustom').addEventListener('click', () => {
    const text = document.getElementById('annText').value || '';
    nui('counter:announce', {type:'custom', text});
  });

  document.getElementById('btnStartRepo').addEventListener('click', () => nui('counter:startRepo', {}));
  async function loadSpots(){
    const r = await nui('counter:getSpots', {});
    counterSpots = (r && r.spots) || [];
    renderSpots();
  }


  // à avoir quelque part au dessus si pas déjà déclarés :
  async function openAssignForm(card, spot) {
    // Nettoyer des formulaires déjà ouverts sur cette carte
    card.querySelectorAll('.assignForm').forEach(el => el.remove());

    const form = document.createElement('div');
    form.className = 'assignForm';
    form.style.marginTop = '8px';
    form.innerHTML = `
      <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center">
        <select class="input" id="selModel" style="flex:1;min-width:260px">
          <option>Chargement…</option>
        </select>
        <input class="input" id="selPlate" placeholder="Plaque (Optionnel)" maxlength="8" style="width:150px" />
        <button class="btn btn-blue" id="btnSaveAssign">OK</button>
        <button class="btn btn-ghost" id="btnCancelAssign">Annuler</button>
      </div>
    `;
    card.appendChild(form);

    // Récupère la liste autorisée selon le type du slot
    const r = await nui('counter:listVehicles', { kind: spot.kind || 'car' });
    const list = (r && r.vehicles) || [];
    const sel = form.querySelector('#selModel');
    sel.innerHTML = '';

    if (!list.length) {
      const opt = document.createElement('option');
      opt.textContent = 'Aucun modèle autorisé';
      opt.disabled = true;
      sel.appendChild(opt);
    } else {
      list.forEach(v => {
        const opt = document.createElement('option');
        opt.value = v.model;
        opt.textContent = `${v.label || v.model} — ${v.category || ''}`;
        sel.appendChild(opt);
      });
    }

    form.querySelector('#btnSaveAssign').addEventListener('click', async () => {
      const model = sel.value;
      const plate = form.querySelector('#selPlate').value || '';
      if (!model) return;
      await nui('counter:spotAssign', { spotId: spot.id, model, plate });
      form.remove();
      await loadSpots(); // rechargement et re-render
    });

    form.querySelector('#btnCancelAssign').addEventListener('click', () => {
      form.remove();
    });
  }

function renderSpots(){
  const grid = document.getElementById('spotsGrid');
  if (!grid) return;
  grid.innerHTML = '';

  const q = (counterSearch || '').toLowerCase().trim();

  const list = (counterSpots || []).filter(s => {
    // filtre par état/type
    if (counterFilter === 'free'     && s.status !== 'free') return false;
    if (counterFilter === 'occupied' && s.status !== 'occupied') return false;
    if (counterFilter === 'reserved' && s.status !== 'reserved') return false;
    if (counterFilter === 'car'      && (s.kind || 'car') !== 'car') return false;
    if (counterFilter === 'bike'     && (s.kind || 'car') !== 'bike') return false;

    // recherche (nom, modèle, plaque)
    if (q){
      const blob = [
        s.name || ('Spot ' + s.id),
        s.vehicle?.label || s.vehicle?.model || '',
        s.vehicle?.plate || ''
      ].join(' ').toLowerCase();
      if (!blob.includes(q)) return false;
    }
    return true;
  });

  list.forEach(s => {
    const status = (s.status === 'free' || s.status === 'reserved') ? s.status : 'occupied';
    const badge  = `<span class="badge ${status}">${status}</span>`;
    const tag    = (s.kind === 'bike')
      ? '<span class="tag tag-bike">🏍️&nbsp;Moto</span>'
      : '<span class="tag tag-car">🚗&nbsp;Voiture</span>';

    const model = s.vehicle ? (s.vehicle.label || s.vehicle.model || '-') : null;
    const plate = s.vehicle?.plate || '—';

    const card = document.createElement('div');
    card.className = 'card';
    card.innerHTML = `
      <div class="slotHead">
        <div style="display:flex;gap:8px;align-items:center">
          <div style="font-weight:700">${s.name || ('Spot ' + s.id)}</div>
          ${tag}
        </div>
        ${badge}
      </div>

      <div class="small" style="margin-top:6px">
        ${model
          ? `<div>Modèle <b>${model}</b></div><div>Plaque ${plate}</div>`
          : `Aucun véhicule`
        }
      </div>

      <div class="actions" style="margin-top:8px">
        <button class="btn"        data-act="assign">Assigner</button>
        <button class="btn btn-blue" data-act="spawn">Spawn</button>
        <button class="btn"        data-act="retire">Retirer</button>
      </div>
    `;

    // Clic rapide sur la carte
    card.addEventListener('click', async (e)=>{
      if (
        e.target.matches('button,select,input,textarea,label,option') ||
        e.target.closest('.assignForm') ||   
        e.target.closest('.actions')         
      ) {
        return;
      }
      if (s.status === 'free'){
        if (s.vehicle?.model || s.vehicle?.label){
          await nui('counter:spotSpawn', { spotId: s.id });
        } else {
           openAssignForm(card, s);
          return; 
        }
      } else if (s.status === 'occupied'){
        await nui('counter:spotClear', { spotId: s.id });
      } 
      await loadSpots(); 
    });

    // Boutons
    card.querySelectorAll('button').forEach(btn=>{
      btn.addEventListener('click', async ()=>{
        const act = btn.getAttribute('data-act');
        if (act === 'assign'){
          openAssignForm(card, s);
          return;
        }
        if (act === 'spawn'){
          await nui('counter:spotSpawn', { spotId: s.id });
        }
        if (act === 'retire'){
          await nui('counter:spotClear', { spotId: s.id });
        }
        if (act === 'reserve'){
          const want = s.status !== 'reserved';
          await nui('counter:spotReserve', { spotId: s.id, reserved: want });
        }
        await loadSpots();
      });
    });

    grid.appendChild(card);
  });
}

  // filtres (Tous/Libres/Occupés/Réservés/Voiture/Moto)
  // document.querySelectorAll('#chipsFilter [data-filter]').forEach(btn => {
  //   btn.addEventListener('click', () => {
  //     counterFilter = btn.dataset.filter;
  //     renderSpots();
  //   });
  // });

  // ===== Logistique =====

function showCounterSection(key){
  // masque tout
  secReception.classList.add('hidden');
  secLogs.classList.add('hidden');

  if (key === 'reception') secReception.classList.remove('hidden');
  if (key === 'logs')      secLogs.classList.remove('hidden');
}

document.querySelectorAll('[data-sec]').forEach(btn=>{
  btn.addEventListener('click', ()=>{
    const key = btn.getAttribute('data-sec');
    if (key==='reception') showCounterSection('reception');
    else if (key==='logs') showCounterSection('logs');
    else showCounterSection(null); // parc & spots par défaut
  });
});

// Permettre au client.lua de forcer l’onglet “reception”
window.addEventListener('message', (e)=>{
  const msg = e.data || {};
  if (msg.action === 'counter:focusSection'){
    showView('counter');
    setTimeout(()=>showCounterSection(msg.section||'reception'), 20);
  }
});

let logi = { list: [], mult: 0.3 };

async function logiLoad(){
  const d = await nui('logi:getStock', { shopId: state.shop?.id });
  logiRows = d.rows || [];
  const cats = [...new Set(logiRows.map(r => r.category || ''))].filter(Boolean).sort();
  logiCat.innerHTML = `<option value="">Toutes catégories</option>` + cats.map(c=>`<option value="${c}">${c}</option>`).join('');
  logiInfo.textContent = `Articles: ${logiRows.length.toLocaleString()} • Multiplicateur réassort: ${Number(d.mult||0).toFixed(2)}x`;
  renderLogi();
  await loadHaulers();
}

function renderLogi(){
  if (!logiList) return;
  const q = (logiSearch.value||'').toLowerCase().trim();
  const cat = logiCat.value || '';
  logiList.innerHTML = '';

  logiRowsFiltered = logiRows.filter(r=>{
    if (cat && r.category !== cat) return false;
    if (q){
      const blob = `${r.name||''} ${r.model||''} ${r.category||''}`.toLowerCase();
      if (!blob.includes(q)) return false;
    }
    return true;
  });

  logiRowsFiltered.forEach(r=>{
    const card = document.createElement('div');
    card.className = 'card';
    card.innerHTML = `
      <div class="title">${r.name || r.model}</div>
      <div class="meta">
        <span class="badge">${Number(r.price||0).toLocaleString()} $</span>
        <span class="badge">Stock: ${Number(r.stock||0)}</span>
        <span class="badge">${r.category || '-'}</span>
      </div>
      <div class="actions">
        <input type="number" min="1" value="1" class="input" style="width:100px" />
        <button class="btn btn-accent" data-act="order">Commander</button>
        <button class="btn" data-act="buyback">Racheter (joueur)</button>
      </div>`;
    const qtyInput = card.querySelector('input');
    // Commander (grossiste)
      card.querySelector('[data-act="order"]').addEventListener('click', async ()=>{
        const qty = Math.max(1, Number(qtyInput.value||1));
        const res = await nui('logi:order', { model: r.model, qty, shopId: state.shop?.id });
        if (res?.ok){ toast(`+${qty} ${r.name||r.model} (stock maj)`, true); await logiLoad(); }
        else { toast(res?.msg || 'Commande impossible', false); }
      });

      // Racheter le véhicule d’un joueur proche et l’ajouter au stock
      card.querySelector('[data-act="buyback"]').addEventListener('click', async ()=>{
        // on prend la personne la plus proche (<= ~8m). L’UI dispose déjà d’une NUI utilitaire.
        const near = await nui('ui:getNearby', { max: 8.0 });
        const players = (near && near.players) || [];
        if (!players.length){ toast('Aucun joueur proche', false); return; }
        const sellerId = players[0].id;

        const res = await nui('logi:buyback', { sellerId, model: r.model, shopId: state.shop?.id });
        if (res?.ok){
          toast('Rachat demandé (stock +1 si validé)', true);
          setTimeout(()=>logiLoad(), 800);
        } else {
          toast(res?.msg || 'Rachat impossible', false);
        }
      });
  });
}

async function loadHaulers(){
  const d = await nui('logi:getHaulers', { shopId: state.shop?.id });
  const haulSel = document.getElementById('haulModel');
  const trailSel = document.getElementById('trailerModel');
  const vehs = d?.vehicles || [];
  const trs  = d?.trailers || [];
  haulSel.innerHTML = vehs.length
    ? vehs.map(x=>`<option value="${x.model}">${x.label||x.model}</option>`).join('')
    : '<option>—</option>';
  trailSel.innerHTML = `<option value="">(Optionnel) Remorque</option>` + (trs.map(x=>`<option value="${x.model}">${x.label||x.model}</option>`).join(''));
}

document.getElementById('btnSpawnHaul')?.addEventListener('click', async ()=>{
  const v = document.getElementById('haulModel')?.value || '';
  const t = document.getElementById('trailerModel')?.value || '';
  if (!v){ toast('Choisissez un utilitaire', false); return; }
  const res = await nui('logi:spawnHauler', { vehicle: v, trailer: t, shopId: state.shop?.id });
  if (!res?.ok) toast(res?.msg || 'Spawn impossible', false);
});

document.getElementById('btnClearHaul')?.addEventListener('click', async ()=>{
  await nui('logi:clearHauler', {});
  toast('Attelage rangé', true);
});


logiSearch?.addEventListener('input', renderLogi);
logiCat?.addEventListener('change', renderLogi);


function updateLogiCost(){
  const model = document.getElementById('logiModel').value;
  const qty   = Math.max(1, Number(document.getElementById('logiQty').value||1));
  const row   = logi.list.find(v => v.model===model);
  const unit  = row ? Number(row.price||0) : 0;
  const cost  = Math.floor(unit * qty * logi.mult);
  document.getElementById('logiCostHint').textContent = `Coût estimé : ${cost.toLocaleString()} $ (×${qty}, mult ${logi.mult})`;
}

document.getElementById('logiModel').addEventListener('change', updateLogiCost);
document.getElementById('logiQty').addEventListener('input', updateLogiCost);

document.getElementById('btnLivraison').addEventListener('click', async ()=>{
  const model = document.getElementById('logiModel').value;
  const qty   = Number(document.getElementById('logiQty').value||1);
  await nui('logi:startLivraison', { model, qty, mult: logi.mult });
});

document.getElementById('btnRestockDirect').addEventListener('click', async ()=>{
  const model = document.getElementById('logiModel').value;
  const qty   = Number(document.getElementById('logiQty').value||1);
  await nui('logi:restockDirect', { model, qty, mult: logi.mult });
});

document.getElementById('btnRepoRandom').addEventListener('click', ()=> nui('counter:startRepo', {}));

async function counterLoad(){
  const d = await nui('counter:getData', {});
  const balEl = document.getElementById('counterBalance');
  if (balEl) balEl.textContent = `Solde: ${Number(d.balance||0).toLocaleString()} $`;
  await loadSpots();
  await receptionLoad();  // ✅
  await histReload();     // ✅
}



logiSearch?.addEventListener('input', renderLogi);
logiCat?.addEventListener('change', renderLogi);


function renderEmpCardBoss(emp) {
  const card = document.createElement('div');
  card.className = 'emp-card';
  card.dataset.identifier = emp.identifier;

  const initials = ((emp.firstname||'')[0]||'').toUpperCase() + ((emp.lastname||'')[0]||'').toUpperCase();
  const grade = Number(emp.job_grade||0);

  card.innerHTML = `
    <div class="emp-avatar">${initials || '👤'}</div>
    <div class="emp-main">
      <div class="emp-name">${(emp.firstname||'') + ' ' + (emp.lastname||'')}</div>
      <div class="emp-role">Grade <span class="emp-grade">${grade}</span></div>
    </div>
    <div class="emp-actions">
      <button type="button" class="pill"              data-act="pay">Payé</button>
      <button type="button" class="pill pill-primary" data-act="grade">Grade</button>
      <button type="button" class="pill pill-warn"    data-act="fire">Virer</button>
    </div>
  `;
  return card;
}

function wireBossClicks(){
  const wrap = document.getElementById('bossEmps');
  if (!wrap) { console.warn('[BOSS_UI] #bossEmps introuvable'); return; }
  if (wrap.dataset.wired === '1') return; // déjà câblé

  wrap.dataset.wired = '1';
  wrap.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-act]');
    if (!btn) return;
    e.preventDefault();
    e.stopPropagation();

    const card = btn.closest('.emp-card');
    if (!card) return;

    const act = btn.getAttribute('data-act');
    const identifier = card.dataset.identifier;
    const currentGrade = Number(card.querySelector('.emp-grade')?.textContent || 0);

    if (act === 'pay') {
      const amount = await popupNumber('Payer un salaire', { min: 1, defaultValue: 1000 });
      if (amount == null) return;
      const r = await nui('boss:payCustom', { identifier, amount: Number(amount) });
      toast(r?.ok ? `Payé ${Number(amount).toLocaleString()} $` : (r?.msg||'Paiement impossible'), !!r?.ok);
      return;
    }

    if (act === 'grade') {
      const action = await popupGradeControls(currentGrade);
      if (!action) return;

      if (action === 'up') {
        if (currentGrade === 3) {
          const ok = await popupConfirm('Passer ce joueur Patron ?', "Il deviendra grade 4 et l'actuel patron sera rétrogradé grade 3.");
          if (!ok) return;
          const r = await nui('boss:promoteToBoss', { identifier });
          toast(r?.ok ? 'Nouveau patron défini' : (r?.msg||'Action impossible'), !!r?.ok);
          await bossLoad();
        } else {
          const r = await nui('boss:changeGrade', { identifier, newGrade: currentGrade + 1 });
          toast(r?.ok ? `Grade ${currentGrade+1}` : (r?.msg||'Action impossible'), !!r?.ok);
          await bossLoad();
        }
        return;
      }

      if (action === 'down') {
        if (currentGrade === 0) return;
        const r = await nui('boss:changeGrade', { identifier, newGrade: currentGrade - 1 });
        toast(r?.ok ? `Grade ${currentGrade-1}` : (r?.msg||'Action impossible'), !!r?.ok);
        await bossLoad();
        return;
      }
    }

    if (act === 'fire') {
      const ok = await popupConfirm('Renvoyer cet employé ?', 'Il passera unemployed 0.');
      if (!ok) return;
      const r = await nui('boss:fire', { identifier });
      toast(r?.ok ? 'Employé renvoyé' : (r?.msg||'Action impossible'), !!r?.ok);
      await bossLoad();
    }
  });

  console.log('[BOSS_UI] Click handler wired sur #bossEmps');
}

async function bossLoad(){
  await reloadBossEmployees()
  const d = await nui('boss:getData', {});
  const bal = document.getElementById('bossBalance');
  if (bal) bal.textContent = `Solde: ${Number(d.balance||0).toLocaleString()} $`;

  const wrap = document.getElementById('bossEmps');
  if (!wrap) { console.warn('[BOSS_UI] #bossEmps introuvable'); return; }

  wrap.innerHTML = '';
  (d.employees || []).forEach(emp => wrap.appendChild(renderEmpCardBoss(emp)));

  // (Re)bind des 3 boutons du header
  const btnRecruit = document.getElementById('btnRecruit');
  const btnAddMoney = document.getElementById('btnAddMoney');
  const btnRemMoney = document.getElementById('btnRemMoney');

  // reset handlers (clone)
  if (btnRecruit)  btnRecruit.replaceWith(btnRecruit.cloneNode(true));
  if (btnAddMoney) btnAddMoney.replaceWith(btnAddMoney.cloneNode(true));
  if (btnRemMoney) btnRemMoney.replaceWith(btnRemMoney.cloneNode(true));

  document.getElementById('btnRecruit')?.addEventListener('click', async ()=>{
    const near = await nui('ui:getNearby', { max: 8.0 });
    const players = near?.players || [];
    if (!players.length) return toast('Aucun joueur proche', false);
    const g = await popupRecruitGrade();
    if (g == null) return;
    const res = await nui('boss:recruit', { targetId: players[0].id, grade: g });
    toast(res?.ok ? 'Recruté' : (res?.msg||'Recrutement impossible'), !!res?.ok);
    if (res?.ok) bossLoad();
  });

  document.getElementById('btnAddMoney')?.addEventListener('click', async ()=>{
    const v = await popupNumber("Ajouter de l'argent à l'entreprise", { min: 1, defaultValue: 1000 });
    if (v == null) return;
    await nui('boss:addMoney', { amount: Number(v) });
    await bossLoad();
  });

  document.getElementById('btnRemMoney')?.addEventListener('click', async ()=>{
    const v = await popupNumber("Retirer de l'argent de l'entreprise", { min: 1, defaultValue: 1000 });
    if (v == null) return;
    await nui('boss:removeMoney', { amount: Number(v) });
    await bossLoad();
  });

  // ⚡️ câblage des boutons des cartes (une seule fois)
  wireBossClicks();
}


async function reloadBossEmployees() {
  const wrap = document.getElementById('bossEmps');
  if (!wrap) return;

  // Indicateur visuel de chargement
  wrap.innerHTML = '<div class="small">Mise à jour des employés...</div>';

  // Récupère uniquement les données boss
  const d = await nui('boss:getData', {});
  wrap.innerHTML = ''; // on vide l'ancien contenu

  // Regénère les cartes employé
  (d.employees || []).forEach(emp => wrap.appendChild(renderEmpCardBoss(emp, d)));

  // Réactive les boutons (Grade / Virer / Payé)
  wireBossClicks();
}


function miniPopup({ title='', bodyHTML='', confirm='Confirmer', cancel='Annuler' }){
  return new Promise(resolve=>{
    const wrap = document.createElement('div');
    wrap.className = 'miniPop';
    wrap.innerHTML = `
      <div class="miniPop__bg"></div>
      <div class="miniPop__win">
        <div class="miniPop__title">${title}</div>
        <div class="miniPop__body">${bodyHTML}</div>
        <div class="miniPop__actions">
          <button class="btn btn-ghost" data-act="cancel">${cancel}</button>
          <button class="btn btn-blue"  data-act="ok">${confirm}</button>
        </div>
      </div>`;
    document.body.appendChild(wrap);
    const done = (v)=>{ wrap.remove(); resolve(v); };
    wrap.querySelector('.miniPop__bg').onclick = ()=>done(null);
    wrap.querySelector('[data-act="cancel"]').onclick = ()=>done(null);
    wrap.querySelector('[data-act="ok"]').onclick = ()=>done(true);
  });
}


async function popupGradeControls(current){
  const downDisabled = current === 0 ? 'disabled' : '';
  const html = `
    <div style="display:flex;gap:8px">
      <button class="pill pill-ghost" id="gDown" ${downDisabled}>Descendre</button>
      <button class="pill pill-primary" id="gUp">Monter</button>
    </div>
    <div class="small">Grade actuel : <b>${current}</b></div>`;
  const wrap = document.createElement('div');
  wrap.innerHTML = html;
  // on crée un vrai popup pour capter lequel a été cliqué
  return new Promise(async (resolve)=>{
    const pop = document.createElement('div');
    pop.className = 'miniPop';
    pop.innerHTML = `
      <div class="miniPop__bg"></div>
      <div class="miniPop__win">
        <div class="miniPop__title">Modifier le grade</div>
        <div class="miniPop__body">${wrap.innerHTML}</div>
        <div class="miniPop__actions">
          <button class="btn btn-ghost" data-act="cancel">Fermer</button>
        </div>
      </div>`;
    document.body.appendChild(pop);
    const done = (v)=>{ pop.remove(); resolve(v); };
    pop.querySelector('.miniPop__bg').onclick = ()=>done(null);
    pop.querySelector('[data-act="cancel"]').onclick = ()=>done(null);
    pop.querySelector('#gUp').onclick = ()=>done('up');
    const gDown = pop.querySelector('#gDown');
    if (gDown) gDown.onclick = ()=>done('down');
  });
}

async function popupConfirm(title, text){
  const html = `<div>${text||''}</div>`;
  const ok = await miniPopup({ title, bodyHTML: html, confirm:'Valider', cancel:'Annuler' });
  return !!ok;
}

async function popupRecruitGrade(){
  return new Promise((resolve) => {
    const pop = document.createElement('div');
    pop.className = 'miniPop';
    pop.innerHTML = `
      <div class="miniPop__bg"></div>
      <div class="miniPop__win">
        <div class="miniPop__title">Recruter</div>
        <div class="miniPop__body">
          <div class="small" style="margin-bottom:6px">Grade d'entrée</div>
          <div style="display:flex;gap:6px;flex-wrap:wrap">
            <label class="pill"><input type="radio" name="rg" value="0" checked />&nbsp;0</label>
            <label class="pill"><input type="radio" name="rg" value="1" />&nbsp;1</label>
            <label class="pill"><input type="radio" name="rg" value="2" />&nbsp;2</label>
            <label class="pill"><input type="radio" name="rg" value="3" />&nbsp;3</label>
          </div>
        </div>
        <div class="miniPop__actions">
          <button class="btn btn-ghost" data-act="cancel">Annuler</button>
          <button class="btn btn-blue"  data-act="ok">Recruter</button>
        </div>
      </div>
    `;
    document.body.appendChild(pop);

    const done = (val) => { pop.remove(); resolve(val); };

    pop.querySelector('.miniPop__bg').onclick = () => done(null);
    pop.querySelector('[data-act="cancel"]').onclick = () => done(null);
    pop.querySelector('[data-act="ok"]').onclick = () => {
      const sel = pop.querySelector('input[name="rg"]:checked');
      const grade = sel ? Number(sel.value) : 0;
      done(grade);
    };
  });
}

// === Petit popup numérique (montant) ===
function quickNumberPopup({ title = 'Montant', min = 1, defaultValue = 1 } = {}) {
  return new Promise((resolve) => {
    const wrap = document.createElement('div');
    wrap.className = 'quickpop';
    wrap.innerHTML = `
      <div class="quickpop__bg"></div>
      <div class="quickpop__win">
        <div class="quickpop__title">${title}</div>
        <div class="quickpop__body">
          <label class="qp_row" style="width:100%">
            <span>Montant</span>
            <input id="qp_amount" type="number" class="input" style="width:160px" min="${min}" value="${defaultValue}">
          </label>
        </div>
        <div class="quickpop__actions">
          <button class="btn btn-ghost" id="qp_cancel">Annuler</button>
          <button class="btn btn-blue"  id="qp_ok">Confirmer</button>
        </div>
      </div>
    `;
    document.body.appendChild(wrap);

    const done = (val) => {
      document.removeEventListener('keydown', onKey);
      wrap.remove();
      resolve(val);
    };
    const onKey = (e) => { if (e.key === 'Escape') done(null); };
    document.addEventListener('keydown', onKey);

    const amountEl = wrap.querySelector('#qp_amount');
    setTimeout(() => amountEl?.focus?.(), 0);

    wrap.querySelector('#qp_cancel').onclick = () => done(null);
    wrap.querySelector('#qp_ok').onclick = () => {
      const v = Math.max(min, Number(amountEl.value||0));
      if (!Number.isFinite(v) || v < min) return;
      done(v);
    };
    wrap.querySelector('.quickpop__bg').onclick = () => done(null);
  });
}


function popupNumber(title, opts = {}) {
  // redirige vers quickNumberPopup pour éviter l'undefined
  return quickNumberPopup({ title, ...(opts || {}) });
}


// === BOSS: Options (recruter / ajouter / retirer argent) ===
document.getElementById('btnAddMoney')?.addEventListener('click', async () => {
  const v = await popupNumber("Ajouter de l'argent à l'entreprise", { min: 1, defaultValue: 1000 });
  if (!v) return;
  const r = await nui('boss:addMoney', { amount: Number(v) });
  // Le serveur notifie déjà; on recharge l’état
  await bossLoad();
});

document.getElementById('btnRemMoney')?.addEventListener('click', async () => {
  const v = await popupNumber("Retirer de l'argent de l'entreprise", { min: 1, defaultValue: 1000 });
  if (!v) return;
  const r = await nui('boss:removeMoney', { amount: Number(v) });
  await bossLoad();
});


  closeBtn.addEventListener('click', () => nui('ui:close'));

  function buildCategories(categories) {
    catsDiv.innerHTML = '';
    state.categories = categories;
    if (!categories.length) {
      catsDiv.innerHTML = `<div class="small">Aucune catégorie disponible ici.</div>`;
      vehList.innerHTML = '';
      return;
    }
    categories.forEach(cat => {
      const el = document.createElement('div');
      el.className = 'cat';
      el.innerHTML = `
        ${cat.image ? `<img src="${cat.image}" alt="">` : ''}
        <div class="name">${cat.label || cat.name}</div>
      `;
      el.addEventListener('click', () => loadVehicles(cat.name));
      catsDiv.appendChild(el);
    });
    // auto-select first
    loadVehicles(categories[0].name);
  }

  async function loadVehicles(categoryName) {
    state.currentCat = categoryName;
    vehList.innerHTML = '';
    const res = await nui('ui:getVehicles', { category: categoryName });
    const items = (res && res.vehicles) || [];
    if (!items.length) {
      vehList.innerHTML = `<div class="small">Pas de véhicules dans cette catégorie.</div>`;
      return;
    }
    items.forEach(v => {
      const card = document.createElement('div');
      card.className = 'card';
      card.innerHTML = `
        <div class="media">
          ${v.image
            ? `<img src="${v.image}" alt="${v.label}" loading="lazy">`
            : `<div class="noimg small">Aucune image</div>`
          }
        </div>
        <div class="title">${v.label}</div>
         <div class="meta" style="align-items:center; justify-content:space-between; width:100%">
           <div class="price smallcard">${v.price.toLocaleString()} $</div>
           <div style="display:flex; gap:6px; flex-wrap:wrap">
             <span class="badge">Stock: ${v.stock ?? 0}</span>
             <span class="badge">Max: ${v.stats?.vmax ?? 0} km/h</span>
           </div>
         </div>
        <div class="actions">
          <button class="btn btn-primary">Détails</button>
          <button class="btn btn-blue">Visualiser</button>
        </div>
      `;
      card.querySelector('.btn-primary').addEventListener('click', () => openPanel(v));
      card.querySelector('.btn-blue').addEventListener('click', () => preview(v));
      vehList.appendChild(card);
    });
  }

  async function preview(v) {
    await nui('ui:preview', { model: v.model });
    state.currentVeh = v;
    enterPeek(); 
  }


  function statBar(pct) {
    pct = Math.max(0, Math.min(100, Number(pct)||0));
    return `<div class="statbar"><i style="width:${pct}%"></i></div>`;
  }

  function openPanel(v) {
    state.currentVeh = v;
    state.primary = '#000000';
    state.secondary = '#000000';

    const canBuy = state.autoBuyAllowed && Number(v.stock ?? 0) > 0;

    panel.innerHTML = `
      <div class="detail__head">
        <h3 id="vehTitle" class="detail__title">${v.label}</h3>
        <div class="detail__sub small">${v.model} • ${v.category} • Stock: ${v.stock ?? 0}</div>
      </div>

      <div class="detail__hero">
        ${v.image ? `<img src="${v.image}" alt="${v.label}">` : `<div class="noimg small">Aucune image</div>`}
      </div>

      <div class="detail__priceRow">
        <div class="price">${v.price.toLocaleString()} $</div>
        <div class="detail__actions">
          <button class="btn btn-blue" id="btnPreview">Visualiser</button>
          ${
            canBuy
              ? `<button class="btn btn-accent" id="btnBuy">Acheter (dispo)</button>`
              : `<button class="btn" disabled title="${state.autoBuyAllowed ? 'Rupture de stock' : 'Vendeur en ville'}">
                  ${state.autoBuyAllowed ? 'Indisponible' : 'Vendeur présent'}
                </button>`
          }
        </div>
      </div>

      <div class="sep"></div>

      <div class="row"><label>Vitesse max</label><div style="flex:1">${statBar(v.stats?.vmax/4)}</div></div>
      <div class="row"><label>Freinage</label><div style="flex:1">${statBar(v.stats?.brake)}</div></div>
      <div class="row"><label>Accélération</label><div style="flex:1">${statBar(v.stats?.accel)}</div></div>

      <div class="sep"></div>

      <div class="row">
        <label>Couleur (prim.)</label>
        <input type="color" id="cPrim" value="#000000" />
        <label>Secondaire</label>
        <input type="color" id="cSec" value="#000000" />
      </div>
    `;

    openModal();

    panel.querySelector('#cPrim').addEventListener('input', recolor);
    panel.querySelector('#cSec').addEventListener('input', recolor);
    panel.querySelector('#btnPreview').addEventListener('click', () => preview(v));
    if (canBuy) panel.querySelector('#btnBuy').addEventListener('click', () => buySelf(v));
}




  async function recolor() {
    const primary = document.getElementById('cPrim').value || '#000000';
    const secondary = document.getElementById('cSec').value || '#000000';
    state.primary = primary; state.secondary = secondary;
    await nui('ui:recolor', { primary, secondary });
  }

  async function buySelf(v) {
    const res = await nui('ui:buySelf', {
      name: v.name, label: v.label, price: v.price, model: v.model, stock: v.stock,
      pay: state.pay, color: state.primary
    });
    if (res?.ok) {
      await nui('ui:close');     // -> client.lua fermera cam + preview + focus et renverra action 'close' à l'UI
    } else {
      toast(res?.msg || 'Erreur achat', false);
    }
  }

  function toast(text, ok){
    const el = document.createElement('div');
    el.textContent = text;
    el.style.position='fixed'; el.style.right='16px'; el.style.top='16px';
    el.style.background = ok ? 'var(--accent)' : 'var(--danger)';
    el.style.color = ok ? '#08110d' : '#fff';
    el.style.padding='8px 12px'; el.style.borderRadius='12px';
    el.style.boxShadow='0 8px 20px rgba(0,0,0,.35)';
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2200);
  }

  // Signale au client Lua que l'UI est prête
  window.addEventListener('DOMContentLoaded', () => {
    nui('ui:ready', {});
  });
})();