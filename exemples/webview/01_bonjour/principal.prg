&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& webview : le minimum. Une page HTML dans une fenêtre native ; le bouton
&& appelle la procédure Lexis+ SALUER (JavaScript -> Lexis+) et affiche sa réponse.
&& Lancement : wdlexisrt exemples/webview/01_bonjour/principal.prg

f = webview.fenetre{titre = "Bonjour webview", largeur = 520, hauteur = 340, html = PAGE()}
f:lier("saluer", @SALUER)          && crée la fonction JavaScript window.saluer(nom)
f:executer()                       && rend la main quand la fenêtre est fermée
? "fenêtre fermée"

fonction SALUER(nom)
  si nom = nul ou nom = ""
    nom = "inconnu"
  finsi
retourner "Bonjour " + nom + " ! (réponse de Lexis+ à " + heure() + ")"

fonction PAGE()
retourner [[<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<style>
  body { font-family: system-ui, sans-serif; margin: 0; height: 100vh; display: grid;
         place-items: center; background: #f4f1ea; color: #222; }
  main { background: #fff; padding: 28px 32px; border-radius: 12px;
         box-shadow: 0 6px 24px rgba(0,0,0,.08); min-width: 360px; }
  h1 { font-size: 20px; margin: 0 0 16px; }
  input { font: inherit; padding: 8px 10px; border: 1px solid #ccc; border-radius: 6px; width: 180px; }
  button { font: inherit; padding: 8px 14px; border: 0; border-radius: 6px;
           background: #2f5d8a; color: #fff; cursor: pointer; }
  #reponse { margin-top: 16px; min-height: 1.4em; color: #2f5d8a; }
</style>
</head>
<body>
<main>
  <h1>Lexis+ &amp; webview</h1>
  <input id="nom" placeholder="Votre prénom" autofocus>
  <button id="go">Saluer</button>
  <div id="reponse"></div>
</main>
<script>
  async function envoyer() {
    const nom = document.getElementById('nom').value;
    // saluer() est la procédure Lexis+ SALUER, liée par f:lier("saluer", @SALUER) ;
    // l'appel renvoie une Promise résolue avec la valeur retournée par Lexis+.
    const reponse = await saluer(nom);
    document.getElementById('reponse').textContent = reponse;
  }
  document.getElementById('go').addEventListener('click', envoyer);
  document.getElementById('nom').addEventListener('keydown', e => { if (e.key === 'Enter') envoyer(); });
</script>
</body>
</html>]]
