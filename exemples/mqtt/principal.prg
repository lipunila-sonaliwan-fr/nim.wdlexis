&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Maison connectée : le protocole MQTT avec le paquet mqtt (Nim pur).
&&
&&   wdlexisrt exemples/mqtt/principal.prg              serveur intégré (port 1883, ou libre)
&&   wdlexisrt exemples/mqtt/principal.prg hote [port]  serveur externe (Mosquitto, EMQX…)
&&
&& Quatre clients MQTT parlent à travers le serveur :
&&   capteurs   publie températures et humidité chaque seconde (QoS 0) ;
&&              son testament annonce « hors ligne » s'il disparaît ;
&&   lampes     reçoit les commandes maison/<piece>/lampe/commande et publie
&&              l'état maison/<piece>/lampe (QoS 1, retenu) ;
&&   tableau    abonné à maison/# : tableau des sujets, courbes, journal ;
&&   thermostat créé par « Panne du thermostat » : il ne donne plus signe de vie,
&&              le serveur le coupe et publie son testament.

ui = paquet("interface")

PIECES = {"salon", "cuisine", "chambre"}
&& tables indexées par le nom de la pièce (clefs en texte : t[p])
temperatures = {}
humidites = {}
lampesallumees = {}
historique = {}         && 30 dernières températures par pièce
pour i = 1 a #PIECES
  temperatures[PIECES[i]] = 22 - i * 1.2
  humidites[PIECES[i]] = 40 + i * 5
  lampesallumees[PIECES[i]] = faux
  historique[PIECES[i]] = {}
suivant
lignes = {}             && sujet -> ligne du tableau
nlignes = 0
serveur = nul
capteurs = nul
thermostat = nul
recus = 0

&& --- serveur ---------------------------------------------------------------
hote = "127.0.0.1"
port = 1883
si #systeme.args >= 1
  hote = systeme.args[1]
  si #systeme.args >= 2
    port = valeur(systeme.args[2])
  finsi
sinon
  essayer
    serveur = mqtt.serveur(1883)
  capturer e
    serveur = mqtt.serveur(0)          && 1883 occupé : port libre
  finessayer
  port = serveur:port()
finsi

&& --- clients ---------------------------------------------------------------
CONNECTER_CAPTEURS()
lampes = mqtt.connecter(hote, port, {id = "lampes", reconnecter = vrai})
lampes:abonner("maison/+/lampe/commande", 1, @COMMANDE_LAMPE)
pour chaque p dans PIECES
  lampes:publier("maison/" + p + "/lampe", "éteinte", {qos = 1, retenu = vrai})
suivant
tableau = mqtt.connecter(hote, port, {id = "tableau", reconnecter = vrai})
tableau:suretat(@ETAT_CONNEXION)

&& --- fenêtre ---------------------------------------------------------------
fen = ui.fenetre{titre = "Maison connectée - MQTT", largeur = 1200, hauteur = 740, disposition = "bordure"}

haut = fen:ajouter(ui.rangee())
haut.ancrage = "haut"
haut.marge = 8
haut.espacement = 8
lblserveur = haut:ajouter(ui.etiquette(""))
lblserveur.poids = 1
bcapteurs = haut:ajouter(ui.bouton("Couper les capteurs"))
bcapteurs.surclic = @BASCULER_CAPTEURS
bpanne = haut:ajouter(ui.bouton("Panne du thermostat (testament)"))
bpanne.surclic = @PANNE

etat = fen:ajouter(ui.etiquette(""))
etat.ancrage = "bas"

sep = fen:ajouter(ui.separateur{vertical = vrai, position = 0.6})
sep.ancrage = "centre"
gauche = sep:ajouter(ui.colonne())
tsujets = gauche:ajouter(ui.tableau())
tsujets:ajoutercolonne("Sujet", 240)
tsujets:ajoutercolonne("Valeur", 130)
tsujets:ajoutercolonne("QoS", 60, "droite")
tsujets:ajoutercolonne("Retenu", 74)
tsujets:ajoutercolonne("Reçu à", 80)
tsujets.poids = 1
tsujets.surselection = @SUJET_CHOISI
courbes = gauche:ajouter(ui.graphe("lignes", "Températures (°C), 30 dernières secondes"))
courbes.hauteurfixe = 260
pour i = 1 a #PIECES
  courbes:libelleserie(i, PIECES[i])
suivant

onglets = sep:ajouter(ui.onglets())
&& Publier
pp = onglets:ajouterpage("Publier")
cpub = pp:ajouter(ui.cadre("Publier un message"))
cpub:ajouter(ui.etiquette("Sujet"))
psujet = cpub:ajouter(ui.saisie("maison/salon/lampe/commande"))
cpub:ajouter(ui.etiquette("Message"))
pmessage = cpub:ajouter(ui.saisie("basculer"))
r1 = cpub:ajouter(ui.rangee())
r1.espacement = 8
r1:ajouter(ui.etiquette("QoS"))
pqos = r1:ajouter(ui.combo("0 - au plus une fois", "1 - au moins une fois", "2 - exactement une fois"))
pqos:selectionner(2)
pretenu = r1:ajouter(ui.cases("retenu"))
bpub = cpub:ajouter(ui.bouton("Publier", {defaut = vrai}))
bpub.surclic = @PUBLIER
clam = pp:ajouter(ui.cadre("Lampes : commande « basculer »", "horizontal"))
pour chaque p dans PIECES
  bl = clam:ajouter(ui.bouton(p))
  bl.surclic = @LAMPE_BOUTON
suivant
cfil = pp:ajouter(ui.cadre("Tester un filtre d'abonnement (jokers + et #)"))
rf = cfil:ajouter(ui.rangee())
rf.espacement = 6
pfiltre = rf:ajouter(ui.saisie("maison/+/lampe"))
pfiltre.poids = 1
ptest = rf:ajouter(ui.saisie("maison/salon/lampe"))
ptest.poids = 1
pfiltre.surchangement = @TESTER_FILTRE
ptest.surchangement = @TESTER_FILTRE
presultat = cfil:ajouter(ui.etiquette(""))
&& Clients
pc = onglets:ajouterpage("Clients")
tclients = pc:ajouter(ui.tableau())
tclients:ajoutercolonne("Client", 110)
tclients:ajoutercolonne("Connecté", 70)
tclients:ajoutercolonne("Abonnements", 240)
tclients.poids = 1
&& Journal du serveur
pj = onglets:ajouterpage("Journal")
journal = pj:ajouter(ui.liste())
journal.poids = 1

tableau:abonner("maison/#", 1, @MESSAGE)
TESTER_FILTRE()
INFOS_SERVEUR()
ui.minuterie(150, @TRAITER)
ui.minuterie(1000, @SIMULER)
ui.executer()

&& --- clients MQTT ----------------------------------------------------------
procedure CONNECTER_CAPTEURS
  globale capteurs
  capteurs = mqtt.connecter(hote, port, {id = "capteurs", maintien = 10, ;
                            testament = {sujet = "maison/capteurs/etat", message = "hors ligne", qos = 1, retenu = vrai}})
  capteurs:publier("maison/capteurs/etat", "en ligne", {qos = 1, retenu = vrai})
retourner

&& Toutes les 150 ms : chaque client reçoit ses messages et les distribue.
procedure TRAITER(ev)
  lampes:traiter()
  tableau:traiter()
  si capteurs <> nul
    capteurs:traiter()
  finsi
  si serveur <> nul
    pour chaque l dans serveur:journal()
      journal:ajouter(l)
    suivant
    si mod(ev.tops, 7) = 0
      CLIENTS()
    finsi
  finsi
retourner

&& Chaque seconde : nouvelles mesures (marche aléatoire).
procedure SIMULER(ev)
  si capteurs = nul ou non capteurs:connecte()
    retourner
  finsi
  pour chaque p dans PIECES
    temperatures[p] = arrondi(temperatures[p] + (aleatoire() - 0.5) * 0.6 + sisinon(lampesallumees[p], 0.05, 0), 1)
    humidites[p] = max(30, min(70, humidites[p] + aleatoire(3) - 2))
    capteurs:publier("maison/" + p + "/temperature", chaine(temperatures[p]))
    capteurs:publier("maison/" + p + "/humidite", chaine(humidites[p]))
  suivant
retourner

&& Client « lampes » : une commande change l'état, publié retenu.
procedure COMMANDE_LAMPE(m)
  locale piece = decouper(m.sujet, "/")[2]
  si lampesallumees[piece] = nul
    retourner
  finsi
  faire cas
  cas minuscule(m.message) = "allumer"
    lampesallumees[piece] = vrai
  cas minuscule(m.message) = "eteindre" ou minuscule(m.message) = "éteindre"
    lampesallumees[piece] = faux
  autrement
    lampesallumees[piece] = non lampesallumees[piece]
  fincas
  lampes:publier("maison/" + piece + "/lampe", sisinon(lampesallumees[piece], "allumée", "éteinte"), ;
                 {qos = 1, retenu = vrai})
retourner

&& Client « tableau » : chaque message reçu met à jour sa ligne (une par sujet).
procedure MESSAGE(m)
  globale nlignes, recus
  recus += 1
  locale i = lignes[m.sujet]
  locale heure = systeme.date("%H:%M:%S", entier(m.horodatage))
  si i = nul
    tsujets:ajouterligne(m.sujet, m.message, chaine(m.qos), sisinon(m.retenu, "oui", ""), heure)
    nlignes += 1
    lignes[m.sujet] = nlignes
  sinon
    tsujets:fixercellule(i, 2, m.message)
    tsujets:fixercellule(i, 3, chaine(m.qos))
    tsujets:fixercellule(i, 4, sisinon(m.retenu, "oui", ""))
    tsujets:fixercellule(i, 5, heure)
  finsi
  locale parts = decouper(m.sujet, "/")
  si #parts = 3 et parts[3] = "temperature" et historique[parts[2]] <> nul
    locale h = historique[parts[2]]
    inserer(h, valeur(m.message))
    si #h > 30
      retirer(h, 1)
    finsi
    COURBES()
  finsi
  etat.libelle = recus + " message(s) reçu(s) par le tableau - dernier : " + m.sujet + " = " + m.message
retourner

procedure COURBES
  pour s = 1 a #PIECES
    locale h = historique[PIECES[s]]
    pour i = 1 a #h
      courbes:ajouterdonnee(s, i, h[i])
    suivant
  suivant
  pour i = 1 a 30
    courbes:libellecategorie(i, sisinon(mod(i, 5) = 0, "-" + (30 - i) + " s", ""))
  suivant
retourner

procedure ETAT_CONNEXION(e)
  etat.libelle = "Tableau : " + sisinon(e = "reconnecte", "reconnecté, abonnements rétablis.", "connexion perdue, nouvelle tentative…")
retourner

&& --- commandes de la fenêtre ----------------------------------------------
procedure PUBLIER(ev)
  essayer
    tableau:publier(rogner(psujet.valeur), pmessage.valeur, {qos = pqos:selection() - 1, retenu = pretenu:coche(1)})
    etat.libelle = "Publié sur " + rogner(psujet.valeur)
  capturer e
    ui.alerte(e, "attention", "Publier")
  finessayer
retourner

procedure LAMPE_BOUTON(ev)
  tableau:publier("maison/" + ev.id.libelle + "/lampe/commande", "basculer", 1)
retourner

procedure TESTER_FILTRE(ev)
  si mqtt.correspond(rogner(pfiltre.valeur), rogner(ptest.valeur))
    presultat.libelle = "✓ le sujet correspond au filtre"
  sinon
    presultat.libelle = "✗ le sujet ne correspond pas au filtre"
  finsi
retourner

procedure SUJET_CHOISI(ev)
  locale i = tsujets:selection()
  si i > 0
    psujet.valeur = tsujets:cellule(i, 1)
    ptest.valeur = tsujets:cellule(i, 1)
    TESTER_FILTRE()
  finsi
retourner

&& Déconnexion propre (pas de testament) ou reconnexion des capteurs.
procedure BASCULER_CAPTEURS(ev)
  globale capteurs
  si capteurs <> nul et capteurs:connecte()
    capteurs:publier("maison/capteurs/etat", "arrêtés", {qos = 1, retenu = vrai})
    capteurs:deconnecter()
    bcapteurs.libelle = "Relancer les capteurs"
  sinon
    CONNECTER_CAPTEURS()
    bcapteurs.libelle = "Couper les capteurs"
  finsi
retourner

&& Un client muet : maintien de 1 s, jamais traité. Le serveur le coupe au bout
&& de 1,5 s et publie son testament (retenu).
procedure PANNE(ev)
  globale thermostat
  thermostat = mqtt.connecter(hote, port, {id = "thermostat", maintien = 1, ;
                              testament = {sujet = "maison/thermostat/etat", message = "PANNE : plus de nouvelles", ;
                                           qos = 1, retenu = vrai}})
  thermostat:publier("maison/thermostat/etat", "en marche", {qos = 1, retenu = vrai})
  etat.libelle = "Thermostat connecté… puis muet : son testament arrive dans 1,5 s."
retourner

procedure INFOS_SERVEUR
  si serveur = nul
    lblserveur.libelle = "Serveur externe " + hote + ":" + port
    retourner
  finsi
  lblserveur.libelle = "Serveur MQTT intégré : port " + port + "   (mosquitto_sub -p " + port + " -t 'maison/#' -v)"
retourner

procedure CLIENTS
  locale st = serveur:statistiques()
  lblserveur.libelle = "Serveur MQTT intégré : port " + port + " - " + st.clients + " client(s), " + ;
                       st.recus + " reçus, " + st.distribues + " distribués, " + st.retenus + " retenus"
  tclients:vider()
  pour chaque c dans serveur:clients()
    locale f = {}
    pour chaque a dans c.abonnements
      inserer(f, a.filtre + " (" + a.qos + ")")
    suivant
    tclients:ajouterligne(c.id, sisinon(c.connecte, "oui", "non"), joindre(f, ", "))
  suivant
retourner
