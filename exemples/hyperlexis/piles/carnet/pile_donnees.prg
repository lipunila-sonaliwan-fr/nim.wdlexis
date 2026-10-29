&& Pile « Carnet d'adresses » : données des cartes (contenu des champs), écrites par HyperLexis.
&& Elles servent au premier lancement ; l'application garde ensuite son état dans
&& pile_donnees.json (à côté du programme) si la persistance est active (pile.prg).
&& Clefs : NOMCARTE -> {NOMCONTROLE -> valeur} ; _PILE -> données de FIXER_DONNEE().

fonction PILE_DONNEES_INITIALES()
retourner dejson("{\"FICHE_1\":{\"NOM\":\"Lovelace\",\"PRENOM\":\"Ada\",\"TELEPHONE\":\"01 23 45 67 89\",\"COURRIEL\":\"ada@exemple.fr\",\"VILLE\":\"4\",\"FAVORI\":\"1\",\"NOTES\":\"Première programmeuse : les notes sur la machine analytique.\"},\"FICHE_2\":{\"NOM\":\"Turing\",\"PRENOM\":\"Alan\",\"TELEPHONE\":\"02 98 76 54 32\",\"COURRIEL\":\"alan@exemple.fr\",\"NOTES\":\"Machine de Turing, test de Turing.\"},\"FICHE_3\":{\"NOM\":\"Hopper\",\"PRENOM\":\"Grace\",\"TELEPHONE\":\"04 72 00 00 00\",\"COURRIEL\":\"grace@exemple.fr\",\"VILLE\":\"2\",\"FAVORI\":\"1\",\"NOTES\":\"Compilateurs, COBOL, et le premier « bug ».\"},\"_PILE\":{}}")
finfonction
