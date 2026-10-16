&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Multitâche : tâches coopératives et fils d'exécution du système
canal = tache.canal()
tache.lancer(@PRODUIRE)
tache.lancer(@CONSOMMER)
tache.executer()

&& un vrai fil d'exécution, avec son propre interpréteur
f = fil.demarrer([[
locale n = fil.recevoir()
locale s = 0
pour i = 1 a n
  s += i
suivant
fil.envoyer({somme = s})
]])
f:envoyer(1000000)
? "somme calculée par le fil :", f:recevoir().SOMME
f:joindre()

procedure PRODUIRE
  pour i = 1 a 5
    canal:envoyer(i * i)
    tache.attendre(0.1)
  suivant
  canal:envoyer("fin")
retourner

procedure CONSOMMER
  tantque vrai
    locale v = canal:recevoir()
    si v = "fin"
      sortir
    finsi
    ? "reçu", v
  fintantque
retourner
