&& Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
&& Objets : tables, procédures associées et métatables (héritage par __index)
personne = {nom = "anonyme"}
personne:procedure PRESENTER comme presenter

moi = NOUVEAU(personne)
lui = NOUVEAU(personne, {nom = "Un autre"})
moi:presenter()
lui:presenter()

fonction NOUVEAU(classe, o)
  si o = nul
    o = {}
  finsi
  classe.__index = classe
retourner fixermetatable(o, classe)

procedure PRESENTER(soi)
  ? "Bonjour, je suis " + soi.nom + "."
retourner
