&& Script de la pile : procédures communes à toutes les cartes.
&& Procédures facultatives appelées par le moteur (pile_moteur.prg) :
&&   SUR_OUVERTURE_PILE()        au lancement de la pile
&&   SUR_FERMETURE_PILE()        à sa fermeture
&&   SUR_OUVERTURE_CARTE(nom)    à chaque carte affichée
&&   SUR_FERMETURE_CARTE(nom)    quand on quitte une carte
&& Fonctions du moteur : ALLER_CARTE, CARTE_SUIVANTE, CARTE_PRECEDENTE, PREMIERE_CARTE,
&& DERNIERE_CARTE, CARTE_RETOUR, CARTE_COURANTE, NUMERO_CARTE, NOMBRE_CARTES, NOUVELLE_CARTE,
&& SUPPRIMER_CARTE, CONTROLE, CHAMP, FIXER_CHAMP, DONNEE, FIXER_DONNEE, TROUVER, MESSAGE.

procedure SUR_OUVERTURE_PILE
  MESSAGE("Carnet d'adresses : " + NOMBRE_CARTES() + " cartes")
finprocedure
