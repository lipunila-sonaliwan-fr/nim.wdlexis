&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& État « stock » - généré par l'éditeur d'états de wdlexis+.
&& Régénéré à chaque modification dans l'éditeur : modifiez le dessin là-bas, pas ce fichier.
&&   r = rapport.debut("stock.pdf")
&&   r.ajoute("zone", {variable = valeur, ...})       zones de l'état : entete, colonnes, rayon, article, soustotal, synthese, pied
&&   r.fin()                                         écrit le PDF

fonction ETAT_STOCK()
retourner [[
{
  "etat": "stock",
  "props": {},
  "zones": [
    {
      "name": "entete",
      "height": 24.0,
      "props": {},
      "items": [
        {
          "kind": "texte",
          "name": "titre",
          "x": 0.0,
          "y": 2.0,
          "w": 120.0,
          "h": 10.0,
          "props": {
            "texte": "Inventaire du stock",
            "taille": "18",
            "gras": "true",
            "couleur": "#1E3A8A"
          }
        },
        {
          "kind": "texte",
          "name": "magasin",
          "x": 0.0,
          "y": 12.0,
          "w": 120.0,
          "h": 6.0,
          "props": {
            "texte": "{magasin}",
            "taille": "10",
            "couleur": "#475569"
          }
        },
        {
          "kind": "texte",
          "name": "date",
          "x": 120.0,
          "y": 4.0,
          "w": 60.0,
          "h": 6.0,
          "props": {
            "texte": "Arrêté au {date}",
            "taille": "9",
            "alignement": "droite"
          }
        },
        {
          "kind": "ligne",
          "name": "trait",
          "x": 0.0,
          "y": 21.0,
          "w": 180.0,
          "h": 0.0,
          "props": {
            "epaisseur": "1",
            "couleur": "#1E3A8A"
          }
        }
      ]
    },
    {
      "name": "colonnes",
      "height": 8.0,
      "props": {},
      "items": [
        {
          "kind": "rectangle",
          "name": "bandeau",
          "x": 0.0,
          "y": 0.0,
          "w": 180.0,
          "h": 7.0,
          "props": {
            "fond": "#E2E8F0",
            "bordure": ""
          }
        },
        {
          "kind": "texte",
          "name": "c1",
          "x": 2.0,
          "y": 1.5,
          "w": 28.0,
          "h": 5.0,
          "props": {
            "texte": "Référence",
            "taille": "8.5",
            "gras": "true"
          }
        },
        {
          "kind": "texte",
          "name": "c2",
          "x": 30.0,
          "y": 1.5,
          "w": 90.0,
          "h": 5.0,
          "props": {
            "texte": "Article",
            "taille": "8.5",
            "gras": "true"
          }
        },
        {
          "kind": "texte",
          "name": "c3",
          "x": 120.0,
          "y": 1.5,
          "w": 15.0,
          "h": 5.0,
          "props": {
            "texte": "Qté",
            "taille": "8.5",
            "gras": "true",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "c4",
          "x": 135.0,
          "y": 1.5,
          "w": 20.0,
          "h": 5.0,
          "props": {
            "texte": "Prix",
            "taille": "8.5",
            "gras": "true",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "c5",
          "x": 155.0,
          "y": 1.5,
          "w": 23.0,
          "h": 5.0,
          "props": {
            "texte": "Valeur",
            "taille": "8.5",
            "gras": "true",
            "alignement": "droite"
          }
        }
      ]
    },
    {
      "name": "rayon",
      "height": 9.0,
      "props": {},
      "items": [
        {
          "kind": "texte",
          "name": "nomrayon",
          "x": 0.0,
          "y": 2.5,
          "w": 180.0,
          "h": 6.0,
          "props": {
            "texte": "{rayon}",
            "taille": "11",
            "gras": "true",
            "couleur": "#B45309"
          }
        }
      ]
    },
    {
      "name": "article",
      "height": 6.0,
      "props": {
        "extensible": "true"
      },
      "items": [
        {
          "kind": "texte",
          "name": "ref",
          "x": 2.0,
          "y": 0.5,
          "w": 28.0,
          "h": 5.0,
          "props": {
            "texte": "{reference}",
            "taille": "8.5",
            "couleur": "#475569"
          }
        },
        {
          "kind": "texte",
          "name": "art",
          "x": 30.0,
          "y": 0.5,
          "w": 88.0,
          "h": 5.0,
          "props": {
            "texte": "{article}",
            "taille": "8.5"
          }
        },
        {
          "kind": "texte",
          "name": "qte",
          "x": 120.0,
          "y": 0.5,
          "w": 15.0,
          "h": 5.0,
          "props": {
            "texte": "{quantite}",
            "taille": "8.5",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "prix",
          "x": 135.0,
          "y": 0.5,
          "w": 20.0,
          "h": 5.0,
          "props": {
            "texte": "{prix:2} €",
            "taille": "8.5",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "val",
          "x": 155.0,
          "y": 0.5,
          "w": 23.0,
          "h": 5.0,
          "props": {
            "texte": "{valeur:2} €",
            "taille": "8.5",
            "alignement": "droite"
          }
        },
        {
          "kind": "ligne",
          "name": "sep",
          "x": 0.0,
          "y": 5.8,
          "w": 180.0,
          "h": 0.0,
          "props": {
            "couleur": "#E2E8F0",
            "epaisseur": "0.3"
          }
        }
      ]
    },
    {
      "name": "soustotal",
      "height": 9.0,
      "props": {},
      "items": [
        {
          "kind": "texte",
          "name": "lib",
          "x": 100.0,
          "y": 1.5,
          "w": 55.0,
          "h": 5.0,
          "props": {
            "texte": "Total {rayon}",
            "taille": "9",
            "gras": "true",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "mt",
          "x": 155.0,
          "y": 1.5,
          "w": 23.0,
          "h": 5.0,
          "props": {
            "texte": "{montant:2} €",
            "taille": "9",
            "gras": "true",
            "alignement": "droite"
          }
        }
      ]
    },
    {
      "name": "synthese",
      "height": 40.0,
      "props": {
        "sautavant": "true"
      },
      "items": [
        {
          "kind": "texte",
          "name": "titre",
          "x": 0.0,
          "y": 0.0,
          "w": 120.0,
          "h": 10.0,
          "props": {
            "texte": "Synthèse",
            "taille": "16",
            "gras": "true",
            "couleur": "#1E3A8A"
          }
        },
        {
          "kind": "rectangle",
          "name": "cadre",
          "x": 0.0,
          "y": 13.0,
          "w": 110.0,
          "h": 24.0,
          "props": {
            "bordure": "#1E3A8A",
            "rayon": "2"
          }
        },
        {
          "kind": "texte",
          "name": "l1",
          "x": 4.0,
          "y": 16.0,
          "w": 60.0,
          "h": 6.0,
          "props": {
            "texte": "Rayons",
            "taille": "10"
          }
        },
        {
          "kind": "texte",
          "name": "v1",
          "x": 64.0,
          "y": 16.0,
          "w": 42.0,
          "h": 6.0,
          "props": {
            "texte": "{rayons}",
            "taille": "10",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "l2",
          "x": 4.0,
          "y": 22.0,
          "w": 60.0,
          "h": 6.0,
          "props": {
            "texte": "Références en stock",
            "taille": "10"
          }
        },
        {
          "kind": "texte",
          "name": "v2",
          "x": 64.0,
          "y": 22.0,
          "w": 42.0,
          "h": 6.0,
          "props": {
            "texte": "{articles}",
            "taille": "10",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "l3",
          "x": 4.0,
          "y": 29.0,
          "w": 60.0,
          "h": 7.0,
          "props": {
            "texte": "Valeur totale",
            "taille": "11",
            "gras": "true"
          }
        },
        {
          "kind": "texte",
          "name": "v3",
          "x": 64.0,
          "y": 29.0,
          "w": 42.0,
          "h": 7.0,
          "props": {
            "texte": "{total:2} €",
            "taille": "11",
            "gras": "true",
            "alignement": "droite"
          }
        }
      ]
    },
    {
      "name": "pied",
      "height": 9.0,
      "props": {},
      "items": [
        {
          "kind": "ligne",
          "name": "trait",
          "x": 0.0,
          "y": 1.0,
          "w": 180.0,
          "h": 0.0,
          "props": {
            "couleur": "#94A3B8",
            "epaisseur": "0.3"
          }
        },
        {
          "kind": "texte",
          "name": "mag",
          "x": 0.0,
          "y": 3.0,
          "w": 120.0,
          "h": 5.0,
          "props": {
            "texte": "{magasin} · inventaire",
            "taille": "7.5",
            "couleur": "#64748B"
          }
        },
        {
          "kind": "texte",
          "name": "num",
          "x": 120.0,
          "y": 3.0,
          "w": 60.0,
          "h": 5.0,
          "props": {
            "texte": "Page {page} / {nombre de page}",
            "taille": "7.5",
            "alignement": "droite",
            "couleur": "#64748B"
          }
        }
      ]
    }
  ]
}
]]
finfonction
