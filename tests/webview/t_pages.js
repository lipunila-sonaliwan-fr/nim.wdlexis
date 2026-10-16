// CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
// Usage : npm i playwright && npx playwright install chromium && node tests/webview/t_pages.js
// Teste le script window.lexis (extrait de pkg_webview.nim) et les pages des exemples
// dans Chromium. window.__lexis et les fonctions liées sont simulés comme webview :
// fonctions globales asynchrones, arguments sérialisés en JSON.
const { chromium } = require('playwright');
const fs = require('fs');
const R = require('path').resolve(__dirname, '../..');
const nim = fs.readFileSync(R + '/src/paquets/pkg_webview.nim', 'utf8');
const helper = nim.split('const HelperJs = """')[1].split('"""')[0].replace('/*CONSOLE*/true', 'true');
let ok = 0, ko = 0;
const verifier = (cond, msg) => { if (cond) { ok++; console.log('  ok  ', msg); } else { ko++; console.log('  ÉCHEC', msg); } };
const attendre = ms => new Promise(r => setTimeout(r, ms));

async function ouvrir(browser, { url, html, binds = {}, lexisSide }) {
  const page = await browser.newPage();
  const recu = [];
  page.on('pageerror', e => recu.push(['pageerror', e.message]));
  // canal interne : window.__lexis(genre, ...)
  await page.exposeFunction('__lexis', async (...a) => { recu.push(a); return lexisSide ? lexisSide(a, page) : null; });
  for (const [nom, fn] of Object.entries(binds)) await page.exposeFunction(nom, fn);
  await page.addInitScript(helper);
  if (!url) { await page.route('http://page.test/', r => r.fulfill({ contentType: 'text/html; charset=utf-8', body: html })); url = 'http://page.test/'; }
  await page.goto(url);
  await attendre(400);
  return { page, recu };
}

(async () => {
  const browser = await chromium.launch();

  console.log('— script window.lexis');
  {
    const { page, recu } = await ouvrir(browser, { html: '<p id=x>x</p><script>function add(a,b){return a+b}; window.app={k:3,get(){return this.k}}; async function lent(){await new Promise(r=>setTimeout(r,50)); return {v:1}}</script>' });
    verifier(recu.some(a => a[0] === 'pret'), 'événement pret envoyé');
    verifier(await page.evaluate('lexis.pret'), 'lexis.pret vrai');
    await page.evaluate('window.lexis._appeler("add",[2,3],1); window.lexis._appeler("app.get",[],2); window.lexis._appeler("lent",[],3); window.lexis._appeler("absente",[],4); window.lexis._evaluer("document.getElementById(\'x\').textContent",5); window.lexis._evaluer("throw new Error(\'boum\')",6); window.lexis._evaluer("1+1",0)');
    await attendre(200);
    const res = id => recu.find(a => a[0] === 'resultat' && a[1] === id);
    verifier(JSON.stringify(res(1)) === '["resultat",1,true,5]', '_appeler add(2,3) -> 5');
    verifier(JSON.stringify(res(2)) === '["resultat",2,true,3]', '_appeler chemin pointé app.get (this conservé)');
    verifier(JSON.stringify(res(3)) === '["resultat",3,true,{"v":1}]', '_appeler fonction async (Promise attendue)');
    verifier(res(4) && res(4)[2] === false && /inconnue : absente/.test(res(4)[3]), '_appeler fonction absente -> erreur');
    verifier(JSON.stringify(res(5)) === '["resultat",5,true,"x"]', '_evaluer expression');
    verifier(res(6) && res(6)[2] === false && res(6)[3] === 'boum', '_evaluer exception -> erreur');
    verifier(!recu.some(a => a[0] === 'resultat' && a[1] === 0), 'sans rappel : aucun résultat renvoyé');
    await page.evaluate('lexis.sur("ev", d => { window.recuEv = d }); window.lexis._emettre("ev", {heure:"12:00"})');
    verifier((await page.evaluate('window.recuEv && window.recuEv.heure')) === '12:00', 'lexis.sur / _emettre');
    await page.evaluate('console.log("bonjour", {a:1}); console.warn("attention"); lexis.journal("j", 2); lexis.envoyer({t:1}); setTimeout(() => { throw new Error("non capturée") }, 0); void Promise.reject(new Error("rejet")); 0');
    await attendre(200);
    verifier(recu.some(a => a[0] === 'journal' && a[1] === 'log' && a[2] === 'bonjour {"a":1}'), 'console.log -> journal');
    verifier(recu.some(a => a[0] === 'journal' && a[1] === 'warn'), 'console.warn -> journal');
    verifier(recu.some(a => a[0] === 'journal' && a[1] === 'info' && a[2] === 'j 2'), 'lexis.journal');
    verifier(recu.some(a => a[0] === 'message' && a[1].t === 1), 'lexis.envoyer -> message');
    verifier(recu.some(a => a[0] === 'journal' && a[1] === 'erreur' && /non capturée/.test(a[2])), 'erreur non capturée -> journal');
    verifier(recu.some(a => a[0] === 'journal' && a[1] === 'erreur' && /rejet/.test(a[2])), 'promesse rejetée -> journal');
    const r = await page.evaluate('lexis.appeler("P", 1, "deux").then(() => "ok")');
    verifier(recu.some(a => a[0] === 'appel' && a[1] === 'P' && JSON.stringify(a[2]) === '[1,"deux"]'), 'lexis.appeler(nom, ...args) -> ["appel", nom, [args]]');
    await page.close();
  }

  console.log('— 01_bonjour');
  {
    const prg = fs.readFileSync(R + '/exemples/webview/01_bonjour/principal.prg', 'utf8');
    const html = prg.split('retourner [[')[1].split(']]')[0];
    const { page, recu } = await ouvrir(browser, { html, binds: { saluer: nom => 'Bonjour ' + (nom || 'inconnu') + ' !' } });
    await page.fill('#nom', 'Ada');
    await page.click('#go');
    await attendre(100);
    verifier((await page.textContent('#reponse')) === 'Bonjour Ada !', 'clic -> saluer("Ada") -> réponse affichée');
    verifier(!recu.some(a => a[0] === 'pageerror'), 'aucune erreur JavaScript');
    await page.close();
  }

  console.log('— 02_lexis_vers_js');
  {
    const { page, recu } = await ouvrir(browser, { url: 'file://' + R + '/exemples/webview/02_lexis_vers_js/page.htm' });
    verifier(recu.some(a => a[0] === 'journal' && a[2] === 'page.htm chargée'), 'console.log de la page -> journal');
    // exactement ce qu'envoie Lexis+ dans PRET (relevé avec la bibliothèque factice)
    await page.evaluate(`window.lexis._appeler("afficher",["Bonjour ! Ce message vient de Lexis+ (16:06:29)."],0);
window.lexis._appeler("ajouterLigne",[{"nom":"Stylo","prix":1.2,"stock":40}],0);
window.lexis._appeler("ajouterLigne",[{"nom":"Cahier","prix":3.5,"stock":12}],0);
window.lexis._appeler("ajouterLigne",[{"nom":"Agrafeuse","prix":14.9,"stock":3}],0);
window.lexis._appeler("calculer",[[{"nom":"Stylo","prix":1.2,"stock":40},{"nom":"Cahier","prix":3.5,"stock":12},{"nom":"Agrafeuse","prix":14.9,"stock":3}]],1);
window.lexis._evaluer("navigator.userAgent",2);
window.lexis._evaluer("document.querySelectorAll('#produits tr').length",3);
window.lexis._appeler("fonctionAbsente",[],4);
window.lexis._appeler("app.theme",["sombre"],0);
window.lexis._emettre("horloge",{"heure":"16:06:29","date":"2026-10-16"});`);
    await attendre(500);
    const res = id => recu.find(a => a[0] === 'resultat' && a[1] === id);
    verifier((await page.textContent('#message')).startsWith('Bonjour !'), 'afficher()');
    verifier(JSON.stringify(res(1)) === '["resultat",1,true,{"total":134.7,"articles":55}]', 'calculer() async -> {total, articles}');
    verifier(res(2) && /Mozilla/.test(res(2)[3]), 'evaluer navigator.userAgent');
    verifier(JSON.stringify(res(3)) === '["resultat",3,true,3]', 'evaluer nombre de lignes = 3');
    verifier(res(4) && res(4)[2] === false, 'fonction absente -> erreur');
    verifier(await page.evaluate('document.body.classList.contains("sombre")'), 'app.theme("sombre")');
    verifier((await page.textContent('#horloge')) === '2026-10-16 16:06:29', 'événement horloge');
    verifier(await page.evaluate('document.querySelector("#produits tr.alerte td").textContent') === 'Agrafeuse', 'stock faible signalé');
    await page.click('text=Remise 10 %');
    await attendre(100);
    verifier(recu.some(a => a[0] === 'message' && a[1].action === 'remise'), 'bouton -> lexis.envoyer({action})');
    verifier(!recu.some(a => a[0] === 'pageerror'), 'aucune erreur JavaScript');
    await page.screenshot({ path: require('os').tmpdir() + '/webview_ex02.png' });
    await page.close();
  }

  console.log('— 03_js_vers_lexis');
  {
    const taux = { normal: 20, intermediaire: 10, reduit: 5.5 };
    const factures = [];
    const ttc = (ht, genre) => {
      const t = taux[genre]; if (t === undefined) throw new Error('taux inconnu : ' + genre);
      const tva = Math.round(ht * t) / 100; return { ht, taux: t, tva, ttc: Math.round((ht + tva) * 100) / 100 };
    };
    const lexisSide = (a) => {
      if (a[0] !== 'appel') return null;
      if (a[1] === 'HISTORIQUE') return factures;
      if (a[1] === 'ENREGISTRER') {
        const f = a[2][0];
        if (!f.client) return { ok: false, message: 'Le nom du client est obligatoire.' };
        const c = Object.assign(ttc(f.ht, f.genre), { client: f.client, numero: factures.length + 1, heure: '12:00:00' });
        factures.push(c); return { ok: true, numero: c.numero, message: 'Facture n°' + c.numero + ' enregistrée.' };
      }
      throw new Error('procédure Lexis+ non autorisée : ' + a[1]);
    };
    const { page, recu } = await ouvrir(browser, { url: 'file://' + R + '/exemples/webview/03_js_vers_lexis/page.htm', lexisSide,
      binds: { taux: () => taux, calculerTTC: (ht, g) => ttc(ht, g) } });
    verifier((await page.$$('#genre option')).length === 3, 'taux() -> 3 options');
    verifier((await page.textContent('#calcul')).includes('120,00 € TTC'), 'calculerTTC(100, normal) affiché');
    await page.click('button.principal');
    await attendre(100);
    verifier((await page.textContent('#calcul')).includes('obligatoire'), 'refus Lexis+ (client vide) affiché');
    await page.fill('#client', 'Durand SA');
    await page.click('button.principal');
    await attendre(200);
    verifier((await page.$$('#historique tr')).length === 1, 'facture enregistrée puis historique affiché');
    verifier(recu.some(a => a[0] === 'message' && a[1].genre === 'info'), 'lexis.envoyer -> surmessage');
    await page.click('#mauvais');
    await attendre(100);
    verifier((await page.textContent('#calcul')).includes('taux inconnu'), 'erreur Lexis+ -> Promise rejetée et affichée');
    verifier(recu.some(a => a[0] === 'journal' && /refus attendu/.test(a[2])), 'appel non autorisé refusé');
    verifier(!recu.some(a => a[0] === 'pageerror'), 'aucune erreur JavaScript');
    await page.screenshot({ path: require('os').tmpdir() + '/webview_ex03.png' });
    await page.close();
  }

  console.log('— 04_application');
  {
    let taches = [], prochain = 1;
    let pageRef;
    const emettre = () => pageRef.evaluate(`window.lexis._emettre("taches", ${JSON.stringify(taches)})`);
    const lexisSide = async (a, page) => {
      pageRef = page;
      if (a[0] === 'pret') { setTimeout(emettre, 0); return null; }
      if (a[0] !== 'appel') return null;
      const [nom, args] = [a[1], a[2]];
      switch (nom) {
        case 'STATISTIQUES': return { total: taches.length, faites: taches.filter(t => t.faite).length, hautes: taches.filter(t => !t.faite && t.priorite === 'haute').length };
        case 'AJOUTER': { const texte = String(args[0]).trim(); if (!texte) throw new Error('Le texte de la tâche est vide.');
          const t = { id: prochain++, texte, faite: false, priorite: args[1] === 'haute' ? 'haute' : 'normale', creee: '2026-10-16' }; taches.push(t); setTimeout(emettre, 0); return t; }
        case 'BASCULER': { const t = taches.find(t => t.id === args[0]); t.faite = !t.faite; setTimeout(emettre, 0); return t.faite; }
        case 'SUPPRIMER': taches = taches.filter(t => t.id !== args[0]); setTimeout(emettre, 0); return true;
        case 'VIDER_FAITES': { const n = taches.filter(t => t.faite).length; taches = taches.filter(t => !t.faite); setTimeout(emettre, 0); return n; }
      }
    };
    const { page, recu } = await ouvrir(browser, { url: 'file://' + R + '/exemples/webview/04_application/page.htm', lexisSide });
    verifier((await page.textContent('#liste')).includes('Rien à faire'), 'liste vide affichée');
    for (const [t, h] of [['Acheter du pain', false], ['Appeler le comptable', true], ['Réserver la salle', false]]) {
      await page.fill('#texte', t); if (h) await page.check('#haute'); await page.click('button.principal'); await attendre(150);
    }
    verifier((await page.$$('#liste li')).length === 3, '3 tâches ajoutées et affichées');
    verifier((await page.$$('#liste li.haute')).length === 1, 'tâche urgente marquée');
    await page.fill('#texte', '   '); await page.click('button.principal'); await attendre(150);
    verifier((await page.textContent('#erreur')).includes('vide'), 'erreur Lexis+ affichée');
    await page.click('#liste li:first-child input[type=checkbox]'); await attendre(150);
    verifier((await page.$$('#liste li.faite')).length === 1, 'tâche cochée');
    verifier((await page.textContent('#stats')).includes('1 faite(s)'), 'statistiques');
    await page.screenshot({ path: require('os').tmpdir() + '/webview_ex04.png' });
    await page.click('#vider'); await attendre(150);
    verifier((await page.$$('#liste li')).length === 2, 'tâches faites retirées');
    verifier(!recu.some(a => a[0] === 'pageerror'), 'aucune erreur JavaScript');
    await page.close();
  }

  await browser.close();
  console.log(`\n${ok} vérifications réussies, ${ko} échec(s)`);
  process.exit(ko ? 1 : 0);
})();
