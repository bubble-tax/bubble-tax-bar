(() => {
  const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const usd = value => `$${value.toFixed(2)}`;
  const icons = {
    back:'m15 5-7 7 7 7', up:'m5 15 7-7 7 7', plan:'M12 20V10m0 0L5 3m7 7 7-7M2 3h6M16 3h6',
    history:'M3 4v6h6M4 9a8 8 0 1 1 0 7m8-9v5l3 2', savings:'M3 6h18v12H3zM6 6v12m12-12v12m-6-9c4 0 4 6 0 6s-4-6 0-6',
    settings:'M9 3h6l1 4 4 1v7l-4 1-1 4H9l-1-4-4-1V8l4-1zM12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8', refresh:'M20 4v6h-6M20 10a8 8 0 1 0-1 7',
  };
  const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[name] || icons.plan}"/></svg>`;
  const defaults = scenario => ({
    page:'overview', section:'next', provider:'claude', scope:'personal', task:'Coding', logProvider:'claude', history:'codex', model:'all', period:'weekly', last30:false,
    review:true, notch:true, login:false, fallback:true, scenario, sheet:null, toast:'', refreshed:0,
    providers:[
      {id:'codex',name:'Codex',full:'ChatGPT / Codex',plan:'Plus',price:20,left:72,session:80,days:4,enabled:true,context:'personal',logs:'/Users/demo/.codex/sessions',rate:2},
      {id:'claude',name:'Claude',full:'Claude',plan:scenario==='work'?'Team':'Max 5x',price:100,left:44,session:45,days:2,enabled:true,context:scenario==='work'?'work':'personal',logs:'/Users/demo/.claude/projects',rate:2},
      {id:'cursor',name:'Cursor',full:'Cursor',plan:'Pro',price:20,left:68,days:12,enabled:true,context:'personal'},
      {id:'copilot',name:'Copilot',full:'GitHub Copilot',plan:'Free',price:0,left:80,days:12,enabled:true,context:'personal'},
      {id:'antigravity',name:'Antigrav.',full:'Antigravity',plan:'Google AI Pro',price:19.99,left:82,days:12,enabled:true,context:'personal'},
    ],
    reservations:[{id:1,provider:'codex',title:'Friday refactor',percent:15,deadline:'Oct 31'},{id:2,provider:'claude',title:'Launch review',percent:25,deadline:'Oct 30'}],
    hours:{codex:2,claude:2}, eligible:{Coding:['codex','claude'],Writing:['codex','claude'],Research:['codex','claude']},
    changes:[{id:1,provider:'cursor',name:'Cursor',kind:'Downgraded',from:'Pro+',to:'Pro',before:60,after:20},{id:2,provider:'copilot',name:'GitHub Copilot',kind:'Cancelled',from:'Pro',to:'Free',before:10,after:0}],
  });
  let instances = 0;
  class BubbleTaxDemo extends HTMLElement {
    connectedCallback() {
      if (this.initialized) return;
      this.initialized = true; this.identity = `bt-${++instances}`; this.state = defaults('personal'); this.disclosures = {};
      this.classList.add('bt-demo'); this.setAttribute('aria-label','Interactive Bubble Tax preview, sample data');
      this.addEventListener('click', event => this.click(event));
      this.addEventListener('change', event => this.change(event));
      this.addEventListener('submit', event => this.submit(event));
      this.addEventListener('toggle', event => { if (event.target.isConnected && event.target.dataset.key) this.disclosures[event.target.dataset.key] = event.target.open; }, true);
      this.addEventListener('cancel', event => { if (event.target.matches('.bt-sheet')) { event.preventDefault(); this.closeSheet(); } }, true);
      this.addEventListener('keydown', event => {
        if (!['ArrowLeft','ArrowRight','Home','End'].includes(event.key) || event.target.getAttribute('role')!=='tab') return;
        const tabs=[...event.target.parentElement.querySelectorAll('[role="tab"]')], at=tabs.indexOf(event.target);
        const next=event.key==='Home'?0:event.key==='End'?tabs.length-1:(at+(event.key==='ArrowRight'?1:-1)+tabs.length)%tabs.length;
        event.preventDefault(); tabs[next].click();
      });
      this.openScreen(this.getAttribute('screen') || 'overview');
    }
    openScreen(screen) {
      const mapping={'use-next':'next',reserve:'reserve',forecast:'forecast',patterns:'patterns',plans:'plans'};
      if (mapping[screen]) { this.state.page='allocation'; this.state.section=mapping[screen]; }
      else if (['model-windows','claude-windows','unused-history'].includes(screen)) { this.state.page='history'; this.state.model='all'; this.state.history=screen==='claude-windows'?'claude':screen==='unused-history'?'unused':'codex'; }
      else this.state.page=screen==='connections'?'settings':screen==='savings'?'savings':'overview';
      this.render(true);
    }
    provider(id=this.state.provider) { return this.state.providers.find(p=>p.id===id); }
    tracked() { return this.state.providers.filter(p=>p.enabled).sort((a,b)=>this.state.review?({codex:0,claude:1}[a.id]??2)-({codex:0,claude:1}[b.id]??2):({claude:0,codex:1}[a.id]??2)-({claude:0,codex:1}[b.id]??2)); }
    get quotaEntries() { return this.tracked().filter(p=>p.price>0).map(p=>({name:p.name,period:p.session===undefined?'Monthly':'Weekly',left:p.left})); }
    setPlacement(mode) { if(this.state.notch!==(mode==='notch')) { this.state.notch=mode==='notch'; this.render(); } }
    closeSheet() { this.state.sheet=null; this.render(); this.restoreSheetFocus(); }
    restoreSheetFocus() { if(this.sheetReturnFocus) [...this.querySelectorAll('[data-focus]')].find(el=>el.dataset.focus===this.sheetReturnFocus)?.focus({preventScroll:true}); }
    lowerPlans(p) { return (p.id==='claude'?[['Free',0],['Pro',20]]:p.id==='antigravity'?[['Free',0]]:p.id==='cursor'?[['Free',0]]:[['Free',0]]).filter(([,price])=>price<p.price); }
    reserved(p) { return this.state.reservations.filter(r=>r.provider===p.id).reduce((sum,r)=>sum+r.percent,0); }
    available(p) { return Math.max(0,p.left-this.reserved(p)); }
    budgets(eligible=false) { return this.tracked().filter(p=>p.session!==undefined && p.context===this.state.scope && (!eligible || this.state.eligible[this.state.task].includes(p.id))); }
    suggestion() { return this.budgets(true).filter(p=>p.session>0&&this.available(p)>0).sort((a,b)=>this.available(b)-this.available(a))[0]; }
    button(label,action,value='',extra='') { return `<button type="button" data-act="${action}" data-value="${escape(value)}" data-focus="${action}:${escape(value)}" ${extra}>${label}</button>`; }
    tool(label,name,action,value='') { return this.button(icon(name),action,value,`class="bt-tool" aria-label="${escape(label)}" title="${escape(label)}"`); }
    bar(value, label='Quota left') { return `<progress max="100" value="${value}" aria-label="${escape(label)}">${Math.round(value)}%</progress>`; }
    card(content,extra='') { return `<div class="bt-card ${extra}">${content}</div>`; }
    details(key,label,content) { return `<details data-key="${key}" ${this.disclosures[key]?'open':''}><summary>${label}</summary><div class="bt-disclosure">${content}</div></details>`; }
    segments(items,current,action,label) { return `<div class="bt-segments" role="tablist" aria-label="${label}">${items.map(([id,name])=>this.button(escape(name),action,id,`role="tab" aria-selected="${id===current}" tabindex="${id===current?0:-1}" aria-controls="${this.identity}-panel"`)).join('')}</div>`; }
    render(resetScroll=false) {
      const previous=this.querySelector('.bt-scroll')?.scrollTop || 0, focus=document.activeElement?.closest('.bt-demo')===this?document.activeElement.dataset.focus:null;
      const s=this.state, overview=s.page==='overview';
      if (!this.tracked().some(p=>p.id===s.provider)) s.provider=this.tracked()[0]?.id || 'codex';
      const title={overview:'Bubble Tax',allocation:'Allocation',history:'Quota history',settings:'Settings',savings:'Savings'}[s.page];
      this.innerHTML=`<section class="bt-app" aria-label="Bubble Tax sample app">
        <header class="bt-toolbar">${!overview?this.tool('Back to overview','back','nav','overview'):''}<strong tabindex="-1">${title}</strong><span class="bt-spacer"></span>${overview?this.tool('Allocation planner','plan','nav','allocation')+this.tool('Quota history','history','nav','history')+this.tool('Savings history','savings','nav','savings'):''}${overview||s.page==='allocation'?this.tool('Settings','settings','nav','settings'):''}${this.hasAttribute('collapsible')?this.tool('Collapse preview','up','collapse'):''}</header>
        ${s.page==='allocation'?this.allocationHeader():''}
        ${s.page==='history'?this.segments([['unused','Unused quota'],['claude','Claude'],['codex','Codex']],s.history,'history','History'):''}
        <div class="bt-scroll" id="${this.identity}-panel" tabindex="0" aria-label="${title} content" ${['allocation','history'].includes(s.page)?'role="tabpanel"':''}>${this[s.page]()}</div>
        <footer class="bt-footer">${this.button('Refresh','refresh')}<span role="status">${escape(s.toast || (s.refreshed?'Sample updated':'9:41 AM'))}</span></footer>
      </section><div class="bt-demo-tools"><label>Sample <select data-change="scenario" aria-label="Demo sample"><option value="personal" ${s.scenario==='personal'?'selected':''}>Personal plans</option><option value="work" ${s.scenario==='work'?'selected':''}>Work account</option></select></label>${this.button('Reset demo','reset')}</div>${s.sheet?this.sheet():''}`;
      const area=this.querySelector('.bt-scroll'); area.scrollTop=resetScroll?0:previous;
      const dialog=this.querySelector('.bt-sheet');
      if (dialog) dialog.showModal();
      else if (focus) ([...this.querySelectorAll('[data-focus]')].find(el=>el.dataset.focus===focus) || this.querySelector('[role=tab][aria-selected=true]') || this.querySelector('.bt-toolbar strong'))?.focus({preventScroll:true});
      this.dispatchEvent(new CustomEvent('demo-change',{detail:this.quotaEntries,bubbles:true}));
      const screen=s.page==='allocation'?({next:'use-next'}[s.section] || s.section):s.page==='history'?({codex:'model-windows',claude:'claude-windows',unused:'unused-history'}[s.history]):s.page==='settings'?'connections':s.page;
      this.dispatchEvent(new CustomEvent('demo-screen',{detail:screen,bubbles:true}));
    }
    overview() {
      const s=this.state, p=this.provider(), next=this.suggestion(), tracked=this.tracked();
      if (!tracked.length) return `<h3>No services selected.</h3><p>Choose the services to track in Settings.</p>${this.button('Connect services…','nav','settings')}`;
      const work=s.scenario==='work', personal=tracked.filter(p=>p.context==='personal'), total=personal.reduce((sum,p)=>sum+p.price,0), weekly=tracked.filter(p=>p.session!==undefined);
      const left=Math.round(weekly.reduce((sum,p)=>sum+p.left,0)/Math.max(1,weekly.length));
      return `${this.button(`<span>${icon('plan')}</span><span><b>${next?'Suggested next · '+next.name:'Plan your AI work'}</b><small>Keep headroom for the work that matters.</small></span><span>›</span>`,'nav','allocation','class="bt-suggestion"')}
        <div class="bt-persona"><img src="assets/${work?'corporateSponsor':'fomoCollector'}.png" alt="" width="52" height="52"><div><h3>${work?'The Corporate Sponsor':'The Subscription Collector'}</h3><p>${work?'Your boss bought the headroom. Give it a job.':"Collecting subscriptions like trading cards. This week's quota collection is looking healthy."}</p></div></div>
        <div class="bt-totals"><span class="bt-ring" style="--left:${left}%" aria-hidden="true"></span><div><b>~${left}% left</b><small>Weekly · ${weekly.length}/${tracked.filter(p=>p.price>0).length} plans</small></div><div class="bt-right"><b>${usd(total)} / mo</b><small>Personal list-price estimate</small></div></div>
        ${this.button(`${icon('savings')} <b>${usd(this.savingsAmount())} / mo less</b><span class="bt-spacer"></span><small>Estimated ›</small>`,'nav','savings','class="bt-summary-link"')}
        ${tracked.length>1?`<small class="bt-muted">Quota left</small><div class="bt-services">${tracked.map(v=>this.button(`<b>${v.name}</b><small>${v.session!==undefined?'5h '+v.session+'%':'Mo '+v.left+'%'}</small>${this.bar(v.session ?? v.left,v.name+' short window left')}${v.session!==undefined?`<small>Wk ${v.left}%</small>${this.bar(v.left,v.name+' weekly left')}`:''}`,'provider',v.id,`aria-pressed="${p.id===v.id}"`)).join('')}</div>`:''}
        <div class="bt-row bt-service-title"><h3>${p.full}</h3><details class="bt-actions"><summary>Plan actions</summary><div>${this.button('Cancellation options…','sheet','provider')}${this.button('Compare downgrade…','sheet','compare')}${this.button('Set renewal schedule…','sheet','renewal')}${this.button('Record completed change…','sheet','change')}</div></details></div>
        <p class="bt-muted">${p.plan} · ${p.context==='work'?'Workspace paid':usd(p.price)+' / mo · list price'}</p>
        ${s.renewals?.[p.id]?`<small>Renews ${escape(s.renewals[p.id].date)} · ${escape(s.renewals[p.id].interval)}</small>`:''}
        <div class="bt-roast"><small>Bubble Tax</small><blockquote>${s.refreshed%2?'Your quota has room. Your to-do list has excuses.':p.context==='work'?"Your boss's AI budget would love to meet your workload.":'Your subscription is an AI-company donation.'}</blockquote></div>
        ${p.session!==undefined?this.forecastCard(p):''}
        ${this.card(`<div class="bt-row"><b>${p.session!==undefined?'Weekly':'Monthly'}</b><b>${p.left}% left</b></div>${this.bar(p.left)}<small class="bt-muted">Resets in ${p.days} days</small>`)}
        ${p.session!==undefined?this.card(`<div class="bt-row"><b>5-hour window</b><b>${p.session}% left</b></div>${this.bar(p.session)}<small class="bt-muted">Resets in 2 hours</small>`):''}
        ${this.details('overview-'+p.id,'Details',`<p>Reported plan: ${p.plan}</p><p>Connection: sample provider session · account identified</p>${this.details('receipts-'+p.id,'Reset receipts',`<div class="bt-stat-grid"><span>Recorded resets<b>3</b></span><span>Average unused<b>${p.id==='codex'?90:27}%</b></span></div><p>Only readings observed near reset count. Missing periods stay unknown.</p>`)}<p>Prices are published list prices, not an invoice.</p>`)}
        <small class="bt-muted">Unused: expired windows · last 30 days.</small>`;
    }
    allocationHeader() {
      const s=this.state;
      return `${this.segments([['next','Use next'],['reserve','Reserve'],['forecast','Forecast'],['patterns','Patterns'],['plans','Plans']],s.section,'section','Allocation sections')}
      <div class="bt-filters">${s.section==='patterns'?`<label>Log source <select aria-label="Log source" data-change="logProvider" data-focus="logProvider"><option value="claude" ${s.logProvider==='claude'?'selected':''}>Claude</option><option value="codex" ${s.logProvider==='codex'?'selected':''}>Codex</option></select></label>`:`<label>Accounts <select aria-label="Accounts" data-change="scope" data-focus="scope"><option value="personal" ${s.scope==='personal'?'selected':''}>Personal</option><option value="work" ${s.scope==='work'?'selected':''}>Work</option></select></label>`}${s.section==='next'?`<label>Task <select aria-label="Task" data-change="task" data-focus="task">${['Coding','Writing','Research'].map(w=>`<option ${w===s.task?'selected':''}>${w}</option>`).join('')}</select></label>`:''}</div>`;
    }
    allocation() { return this[this.state.section](); }
    next() {
      const options=this.budgets(true), next=this.suggestion();
      return `<h3>${next?'Use '+next.name+' next.':'Check availability first.'}</h3><p class="bt-muted">${next?'Weekly headroom for your '+this.state.task.toLowerCase()+' queue.':'No ready service in this account group. Try the other scope or change the sample below.'}</p>${next?this.button('View '+next.name+' quota','provider',next.id):''}${options.map(p=>this.card(`<div class="bt-row"><b>${p.name}</b><span>${p.left}% weekly left</span></div>${this.bar(p.left)}<div class="bt-row bt-muted"><span>${p.session}% session left</span><span>Resets ${p.days} days</span></div><small>${this.reserved(p)}% set aside · ${this.available(p)}% unallocated</small>`)).join('')}<small class="bt-muted">Recommendations use available quota, not equivalent work capacity or model quality. Choose suitable services in Settings. Work budgets stay separate.</small>`;
    }
    reserve() {
      const options=this.budgets();
      return `<div class="bt-row"><h3>Save room for real work.</h3>${this.button('Set aside…','sheet','reserve',options.length?'':'disabled')}</div>${options.map(p=>this.card(`<div class="bt-row"><b>${p.name}</b><small>${p.left}% weekly left</small></div><div class="bt-budget-bar" role="img" aria-label="${100-p.left}% used, ${this.reserved(p)}% reserved, ${this.available(p)}% unallocated"><i style="width:${100-p.left}%"></i><i style="width:${Math.min(p.left,this.reserved(p))}%"></i><i></i></div><small>${this.reserved(p)}% set aside · ${this.available(p)}% unallocated</small>${this.reserved(p)>p.left?'<p>Reserved target is at risk.</p>':''}${this.state.reservations.filter(r=>r.provider===p.id).map(r=>`<div class="bt-reservation"><div><b>${escape(r.title)}</b><small>${r.percent}% · ${escape(r.deadline)}</small></div>${this.button('Done','done',r.id)}${this.button('Remove','remove-reservation',r.id)}</div>`).join('')}`)).join('')}${!options.length?'<p>No weekly quota in this account group.</p>':''}<small class="bt-muted">Local planning targets. Reservations don’t lock provider quota. Marking work done releases its target; only provider readings change actual usage.</small>`;
    }
    forecastCard(p) {
      const hours=this.state.hours[p.id] ?? 2, protectedAmount=this.reserved(p), left=p.left-hours*p.rate*p.days-protectedAmount;
      return this.card(`<div class="bt-row bt-muted"><b>Weekly runway</b><b>${p.name}</b></div><h3>${hours===0?'No daily time scheduled':left>=0?'Headroom through reset':'Reserved work may be at risk'}</h3><div class="bt-row"><div class="bt-number">≈ ${Math.max(0,Math.round(left))}%<small>${protectedAmount?'above targets':'left'} at reset</small></div><div class="bt-right">${p.days}.0 days<small>until reset</small></div></div>${this.bar(Math.max(0,Math.min(100,(p.left-protectedAmount)/Math.max(1,hours*p.rate*p.days)*100)),'Runway coverage')}<small class="bt-muted">${hours.toFixed(1)}h/day plan · ≈ ${(hours*p.rate).toFixed(1)} weekly pp/day<br>3 recorded windows</small>`);
    }
    forecast() { return `<h3>Will your plan fit?</h3><p class="bt-muted">Set daily time, then check weekly headroom at your recorded window pace.</p>${this.budgets().map(p=>`<label class="bt-row">${p.name} · hours / day <input type="number" min="0" max="24" step="0.5" value="${this.state.hours[p.id]}" data-change="hours" data-provider="${p.id}" data-focus="hours:${p.id}" aria-label="${p.name} daily hours"></label>${this.forecastCard(p)}`).join('') || '<p>No weekly quota in this account group.</p>'}<small class="bt-muted">The sample estimates use a fixed recorded pace. In the Mac app, forecasts need paired observations and include idle time. They are not guarantees of future capacity.</small>`; }
    patterns() {
      const claude=this.state.logProvider==='claude';
      return `<h3>A closer look at the input.</h3><small class="bt-muted">Code logs on this Mac · last 7 days · across accounts</small>${this.card(`<div class="bt-row"><b>Repeated large inputs</b><span>${claude?'13':'9'} / 112</span></div>${this.bar(claude?12:8,'Large input share')}<p>Several requests carried at least 32K new input tokens. Check repeated files or instructions if unexpected.</p>`)}${this.card(`<div class="bt-row"><b>Reused input</b><b class="bt-number">${claude?79:72}%</b></div>${this.bar(claude?79:72,'Cache read share')}<p>Cache reads as a share of known input tokens. Reuse is context; its billing and quota effect depends on the provider.</p>`)}${this.card(`<b>Models used</b>${this.modelBars(claude)}`)}<small class="bt-muted">112 logged events · 112 with token breakdowns. Records don’t reveal retries, task success or which account paid.</small>`;
    }
    modelBars(claude) { return (claude?[['claude-sonnet-4-5',74],['claude-opus-4-1',26]]:[['gpt-5-codex',67],['gpt-5',33]]).map(([name,share])=>`<div class="bt-row"><span>${name}</span><span>${share}%</span></div>${this.bar(share,name+' token mix')}`).join(''); }
    plans() {
      const options=this.tracked().filter(p=>p.context===this.state.scope);
      return `<h3>A plan for every real need.</h3>${this.state.scope==='personal'?`<div class="bt-number">${usd(options.reduce((sum,p)=>sum+p.price,0))}<small>/ mo · known list prices</small></div>`:''}${options.map(p=>this.card(`<div class="bt-row"><b>${p.name}</b><span>${p.plan}</span></div><h4>${p.context==='work'?'Review shared seat':this.reserved(p)?'Protect planned work':p.price?'Keep headroom':'Free capacity'}</h4><p>${p.context==='work'?'Shared-seat capacity is not personal savings. Review its needs with the workspace owner.':this.reserved(p)?'Pending work has a protected quota target. Keep its needs in the plan.':'Check features, model access and your tasks before changing the plan.'}</p>${p.session!==undefined?`<div class="bt-row"><small>${p.id==='codex'?90:27}% average left at reset</small><small>3 resets</small></div>${this.bar(p.id==='codex'?90:27,'Average quota left at reset')}`:''}${p.price>0&&p.context==='personal'?this.button('Compare tiers…','compare',p.id):''}`)).join('') || '<p>No confirmed plans in this account group.</p>'}<small class="bt-muted">Capacity review, not a quality score. Prices aren’t invoices.</small>`;
    }
    history() {
      const s=this.state;
      if (s.history==='unused') return this.unused();
      const claude=s.history==='claude', name=claude?'Claude':'Codex', models=claude?['claude-sonnet-4-5','claude-opus-4-1']:['gpt-5-codex','gpt-5'];
      const rows=[{session:50,weekly:5,models:[models[0]],date:'Oct 27 · 8:00 AM'},{session:40,weekly:4,models:[models[1]],date:'Oct 27 · 1:00 PM'},{session:20,weekly:3,models,date:'Oct 27 · 6:00 PM'}].filter(r=>s.model==='all'||r.models.includes(s.model));
      return `<h3>${name} · 5-hour → weekly</h3><small class="bt-muted">Last paired reading · sample snapshot<br>All models · ${claude?this.provider('claude').plan:'Plus'}</small><label class="bt-row">Model in logs <select data-change="model" data-focus="model" aria-label="Model in logs"><option value="all">All models</option>${models.map(m=>`<option ${s.model===m?'selected':''}>${m}</option>`).join('')}</select></label>${this.card(`<b>Observed weekly cost</b><small>10.0–15.0 weekly pp / full 5-hour quota</small><svg class="bt-chart" viewBox="0 0 320 135" role="img" aria-label="${rows.length} observed windows comparing five-hour and weekly percentage points"><path d="M28 10v100h280M28 77h280M28 43h280"/><text x="2" y="15">6</text><text x="2" y="80">2</text><text x="25" y="130">0</text><text x="155" y="130">50</text><text x="290" y="130">100</text>${rows.map(r=>`<circle cx="${28+r.session*2.8}" cy="${110-r.weekly*16}" r="4"><title>${r.session} pp five-hour → ${r.weekly} pp weekly</title></circle>`).join('')}</svg><small>5-hour pp · one dot per observed window segment</small><p>Different slopes mean different observed cost. This is not a fixed conversion rule.</p>`)}${rows.slice().reverse().map((r,i)=>this.card(`<div class="bt-row"><b>${r.date}</b><small>${i===0?'In progress':'Recorded'}</small></div><small>5-hour reset · 13 readings</small><h3>+${r.session}.0 pp <span class="bt-muted">→</span> +${r.weekly}.0 pp</h3><small>5-hour <span class="bt-muted">→</span> weekly</small><b>Models used</b><p>${r.models.join(' · ')}</p>${this.details('tokens-'+s.history+'-'+r.date,'Model and token details',`<div class="bt-stat-grid"><span>Input<b>32K</b></span><span>Output<b>8K</b></span><span>Cache read<b>240K</b></span><span>Cache write<b>12K</b></span></div><small>Token mix adds context; it is not quota share.</small>`)}`)).join('')}<small class="bt-muted">Model usage from saved code logs adds context; quota changes are account-wide.</small>${this.details('about-records','About these records','<p>Latest 30 segments · 180 days. pp = percentage points. Resets and plan changes start new segments. Gaps and small changes are excluded from rate comparisons. Code logs may be incomplete and their account ownership is unverified.</p>')}`;
    }
    unused() {
      const records=[{days:35,left:95},{days:14,left:88},{days:7,left:90}].filter(r=>!this.state.last30||r.days<=30);
      return `<h3>The quota left behind.</h3><div class="bt-row"><label>Window <select data-change="period" aria-label="Unused quota window"><option value="weekly" ${this.state.period==='weekly'?'selected':''}>Weekly</option><option value="session" ${this.state.period==='session'?'selected':''}>5-hour</option></select></label><label><input type="checkbox" data-change="last30" ${this.state.last30?'checked':''}> Last 30 days</label></div>${this.card(`<div class="bt-row"><b>Codex · ${this.state.period==='weekly'?'Weekly':'5-hour'}</b><span>${records.length} resets</span></div><div class="bt-reset-chart">${records.map((r,i)=>`<div><b>${this.state.period==='weekly'?r.left:r.left-30}%</b><i style="height:${(this.state.period==='weekly'?r.left:r.left-30)*.9}px"></i><small>${r.days}d ago</small></div>`).join('')}</div>${this.details('unused-receipts','Reset receipts',records.map(r=>`<div class="bt-row"><span>${r.days} days ago</span><b>${this.state.period==='weekly'?r.left:r.left-30}% left</b></div>`).join(''))}`)}<small class="bt-muted">Only near-reset observations count. Missing periods aren’t guessed. Weekly and session limits are separate budgets.</small>`;
    }
    savingsAmount() { return this.state.changes.reduce((sum,c)=>sum+Math.max(0,c.before-c.after),0); }
    savings() { const total=this.savingsAmount(); return `<h3>A smaller monthly bill.</h3><div class="bt-number">${usd(total)}<small>estimated monthly reduction</small></div>${this.card(`<div class="bt-row"><span>Annual rate difference</span><b>${usd(total*12)}</b></div><small>Projected list-price reduction, not cash already recovered.</small>`)}${this.state.changes.map(c=>this.card(`<div class="bt-row"><b>${escape(c.name)}</b><span>${c.kind}</span></div><p>${escape(c.from)} → ${escape(c.to)}</p><div class="bt-row"><span>${usd(c.before)} → ${usd(c.after)} / mo</span><b>${usd(c.before-c.after)} less</b></div>${this.button('Remove record','remove-change',c.id)}`)).join('')}<small class="bt-muted">Completed changes are records you add after acting with the provider. Work seats stay outside personal savings.</small>`; }
    settings() {
      const s=this.state;
      return `<h3>General</h3>${this.toggle('Cancellation candidates first','review',s.review)}${this.toggle('Use MacBook notch','notch',s.notch)}${this.toggle('Open at Login','login',s.login)}<small class="bt-muted">Preview controls only. Your Mac’s settings are not changed.</small><hr><h3>Suitable services</h3><p class="bt-muted">Choose which services you would use for each task.</p>${['Coding','Writing','Research'].map(w=>`<fieldset><legend>${w}</legend>${['codex','claude'].map(id=>`<label><input type="checkbox" data-change="eligible" data-task="${w}" data-provider="${id}" ${s.eligible[w].includes(id)?'checked':''}> ${this.provider(id).name}</label>`).join('')}</fieldset>`).join('')}<hr><h3>Connections</h3><p class="bt-muted">Existing signed-in sessions in the Mac app. Sample connections here.</p>${s.providers.map(p=>`<section class="bt-connection">${this.toggle(p.full,'tracked',p.enabled,p.id)}<small class="bt-muted">${p.enabled?'Connected · sample session':'Tracking off'}<br>Reported plan: ${p.plan}</small>${p.session!==undefined?`<small class="bt-path">${p.logs?'Logs: '+escape(p.logs):'Default: '+(p.id==='claude'?'/Users/demo/.claude/projects':'/Users/demo/.codex/sessions')}</small><div class="bt-wrap">${this.button(p.logs?'Use default folder':'Connect default logs','default-logs',p.id,p.logs==='/Users/demo/'+(p.id==='claude'?'.claude/projects':'.codex/sessions')?'disabled':'')}${this.button('Choose folder…','folder',p.id)}${p.logs?this.button('Disconnect logs','disconnect',p.id):''}</div>`:''}${p.id==='claude'?`${this.button(s.fallback?'Remove quota fallback':'Enable Claude Code quota fallback','fallback')}<small class="bt-muted">Shows quota in Claude Code while connected. Disconnect restores the saved display.</small>`:''}</section>`).join('')}<hr><h3>Pi coding agent</h3><small class="bt-path">${s.pi?'Sessions: /Users/demo/.pi/agent/sessions':'Default: /Users/demo/.pi/agent/sessions'}</small>${this.button(s.pi?'Disconnect sessions':'Connect default sessions','pi')}<small class="bt-muted">Pi uses provider subscriptions or API keys. Session tokens do not establish remaining subscription quota.</small>`;
    }
    toggle(label,action,checked,value='') { return `<label class="bt-toggle"><input type="checkbox" data-change="${action}" data-value="${value}" data-focus="${action}:${value}" ${checked?'checked':''}> ${escape(label)}</label>`; }
    sheet() {
      const s=this.state, kind=s.sheet, p=this.provider(s.sheetProvider || s.provider), options=this.budgets();
      let title='', body='';
      if (kind==='reserve') {
        title='Set aside weekly quota'; const available=options.map(p=>`<option value="${p.id}">${p.name} · ${this.available(p)}% unallocated</option>`).join('');
        const tomorrow=new Date(Date.now()+86400000); const date=new Date(tomorrow.getTime()-tomorrow.getTimezoneOffset()*60000).toISOString().slice(0,16);
        body=`<form data-form="reserve"><label>Service<select name="provider">${available}</select></label><label>Work to protect<input name="title" required maxlength="80" placeholder="What needs headroom?" autofocus></label><label>Weekly quota (%)<input name="percent" type="number" required min="1" max="100" value="10"></label><label>Needed by<input name="deadline" type="datetime-local" value="${date}" required></label><p class="bt-form-error" role="alert"></p><small>Planning target only. Quota isn’t locked with the provider.</small><button type="submit">Set aside</button></form>`;
      } else if (kind==='compare') {
        title='Compare '+p.name+' tiers'; const target=this.lowerPlans(p).at(-1) || ['Free',0], difference=Math.max(0,p.price-target[1]);
        body=`<p>${p.plan} → ${target[0]} · ${usd(target[1])} / mo list price</p>${this.card(`<div class="bt-number">${usd(difference)}<small>potential monthly difference</small></div><p>${usd(difference*12)} / year could go toward a trip, a hobby, or a less impressive auto-renewal habit.</p>`)}<p>Check model access, features and your real tasks before changing tiers.</p><small>Illustrative list-price comparison. Changing this demo does not change a subscription.</small>`;
      } else if (kind==='change') {
        title='Record completed change';
        body=`<p>${p.full} · from ${p.plan}</p><form data-form="change">${p.context==='work'?'<p>Seat released · work budget, not personal savings.</p>':`<label>Completed action<select name="kind" aria-label="Completed action" data-change="change-kind"><option>Cancelled</option><option ${s.changeKind==='Downgraded'?'selected':''}>Downgraded</option></select></label>${s.changeKind==='Downgraded'?`<label>New plan<select name="target" aria-label="New plan">${this.lowerPlans(p).map(([name,price])=>`<option value="${name}">${name} · ${usd(price)} / mo</option>`).join('')}</select></label>`:''}`}<label class="bt-confirm"><input type="checkbox" name="confirmed" required> I completed this with the provider</label><small>Sample record only. No subscription is changed. Monthly reductions use published list prices.</small><button type="submit">Save record</button></form>`;
      } else if (kind==='renewal') {
        title='Renewal schedule'; body=`<form data-form="renewal"><label>Next renewal<input type="date" name="date" required value="${new Date(Date.now()+7*86400000).toISOString().slice(0,10)}"></label><label>Frequency<select name="interval"><option>Monthly</option><option>Yearly</option></select></label><small>User-set schedule, independent of quota reset dates.</small><button type="submit">Save sample schedule</button></form>`;
      } else if (kind==='folder') {
        title='Choose log folder'; body=`<form data-form="folder"><label>Sample folder path<input name="path" required value="${escape(p.logs || '/Users/demo/'+(p.id==='claude'?'.claude/projects':'.codex/sessions'))}" autofocus></label><small>No folders are read by this website. The Mac app opens the system folder picker.</small><button type="submit">Use sample folder</button></form>`;
      } else { title='Manage '+p.name+' subscription'; body='<p>The Mac app opens the provider’s subscription page here.</p><p>This web preview does not access your account or cancel a subscription.</p>'; }
      return `<dialog class="bt-sheet" aria-labelledby="${this.identity}-sheet-title"><div class="bt-row"><h3 id="${this.identity}-sheet-title">${title}</h3>${this.button('Close','close-sheet')}</div>${body}</dialog>`;
    }
    click(event) {
      const button=event.target.closest('button[data-act]'); if (!button || !this.contains(button)) return;
      const {act,value}=button.dataset, s=this.state; let reset=false;
      if (act==='collapse') { this.dispatchEvent(new CustomEvent('demo-collapse',{bubbles:true})); return; }
      if (act==='nav') { s.page=value; reset=true; }
      if (act==='section') { s.section=value; reset=true; }
      if (act==='history') { s.history=value; s.model='all'; reset=true; }
      if (act==='provider') { s.provider=value; s.page='overview'; reset=true; }
      if (['sheet','compare','folder'].includes(act)) this.sheetReturnFocus=button.dataset.focus;
      if (act==='sheet') { s.changeKind='Cancelled'; s.sheet=value; s.sheetProvider=s.provider; }
      if (act==='compare') { s.sheet='compare'; s.sheetProvider=value; }
      if (act==='folder') { s.sheet='folder'; s.sheetProvider=value; }
      if (act==='close-sheet') { this.closeSheet(); return; }
      if (act==='done'||act==='remove-reservation') { s.reservations=s.reservations.filter(r=>r.id!==Number(value)); s.toast=act==='done'?'Target released':'Reservation removed'; }
      if (act==='remove-change') s.changes=s.changes.filter(c=>c.id!==Number(value));
      if (act==='default-logs') this.provider(value).logs='/Users/demo/'+(value==='claude'?'.claude/projects':'.codex/sessions');
      if (act==='disconnect') this.provider(value).logs=null;
      if (act==='fallback') s.fallback=!s.fallback;
      if (act==='pi') s.pi=!s.pi;
      if (act==='reset') { this.state=defaults(s.scenario); this.disclosures={}; reset=true; }
      if (act==='refresh') { s.refreshed++; s.toast='Sample snapshot updated'; for (const p of this.tracked()) { p.left=Math.max(0,p.left-1); if(p.session!==undefined)p.session=Math.max(0,p.session-2); } }
      this.render(reset);
    }
    change(event) {
      const el=event.target, action=el.dataset.change, s=this.state;
      if (!action) return;
      if (action==='change-kind') { s.changeKind=el.value; this.render(); return; }
      if (action==='scenario') { this.state=defaults(el.value); this.disclosures={}; this.render(true); return; }
      if (['review','notch','login','fallback','last30'].includes(action)) s[action]=el.checked;
      if (['scope','task','logProvider','model','period'].includes(action)) s[action]=el.value;
      if (action==='tracked') this.provider(el.dataset.value).enabled=el.checked;
      if (action==='hours') s.hours[el.dataset.provider]=Math.max(0,Math.min(24,Number(el.value)||0));
      if (action==='eligible') s.eligible[el.dataset.task]=el.checked?[...new Set([...s.eligible[el.dataset.task],el.dataset.provider])]:s.eligible[el.dataset.task].filter(id=>id!==el.dataset.provider);
      if (action==='notch') this.dispatchEvent(new CustomEvent('demo-placement',{detail:el.checked?'notch':'menu',bubbles:true}));
      this.render();
    }
    submit(event) {
      const form=event.target.closest('form[data-form]'); if (!form) return; event.preventDefault();
      const data=new FormData(form), s=this.state, kind=form.dataset.form;
      if (kind==='reserve') {
        const p=this.provider(data.get('provider')), percent=Number(data.get('percent')), title=String(data.get('title')).trim(), date=new Date(data.get('deadline'));
        let message='';
        if (!p || !this.budgets().includes(p)) message='Choose an available service.';
        else if (!title) message='Give this task a name.';
        else if (!Number.isFinite(percent)||percent<=0||percent>this.available(p)) message=`Only ${this.available(p)}% is unallocated for ${p.name}.`;
        else if (!Number.isFinite(date.getTime())||date<=new Date()||date>new Date(Date.now()+p.days*86400000)) message='Choose a future deadline before this weekly reset.';
        if (message) { form.querySelector('.bt-form-error').textContent=message; return; }
        s.reservations.push({id:Date.now(),provider:p.id,title,percent,deadline:date.toLocaleDateString('en-US',{month:'short',day:'numeric'})}); s.toast='Sample target saved';
      } else if(kind==='change') {
        const p=this.provider(s.sheetProvider), cancelled=data.get('kind')!=='Downgraded', target=cancelled?['Free',0]:this.lowerPlans(p).find(([name])=>name===data.get('target'));
        if(!data.get('confirmed')||!target)return;
        const previous=s.changes.find(c=>c.provider===p.id);
        s.changes=s.changes.filter(c=>c.provider!==p.id);
        if(p.context==='personal') s.changes.push({id:Date.now(),provider:p.id,name:p.full,kind:cancelled?'Cancelled':'Downgraded',from:previous?.from || p.plan,to:target[0],before:previous?.before ?? p.price,after:target[1]});
        s.toast=p.context==='work'?'Sample seat release recorded':'Sample change recorded';
      } else if(kind==='renewal') { s.renewals ||= {}; s.renewals[s.provider]={date:String(data.get('date')),interval:String(data.get('interval'))}; }
      else if(kind==='folder') { const path=String(data.get('path')).trim(); if(!path)return; this.provider(s.sheetProvider).logs=path; }
      this.closeSheet();
    }
  }
  customElements.define('bubble-tax-demo',BubbleTaxDemo);
})();
