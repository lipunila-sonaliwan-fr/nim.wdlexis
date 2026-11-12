&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Corpus de l'exemple : quelques classiques de la littérature (résumés originaux).

fonction LIVRES()
retourner { ;
  {id = "hugo-1862", titre = "Les Misérables", auteur = "Victor Hugo", annee = 1862, genre = "roman", pages = 1900, ;
   resume = "Jean Valjean, ancien forçat poursuivi par l'inspecteur Javert, tente de se racheter en protégeant la jeune Cosette dans le Paris des barricades de 1832."}, ;
  {id = "hugo-1831", titre = "Notre-Dame de Paris", auteur = "Victor Hugo", annee = 1831, genre = "roman", pages = 940, ;
   resume = "Dans le Paris médiéval, le sonneur Quasimodo, l'archidiacre Frollo et le capitaine Phœbus gravitent autour de la danseuse Esmeralda, à l'ombre de la cathédrale."}, ;
  {id = "hugo-1866", titre = "Les Travailleurs de la mer", auteur = "Victor Hugo", annee = 1866, genre = "roman", pages = 600, ;
   resume = "Sur l'île de Guernesey, le pêcheur Gilliatt affronte l'océan et une pieuvre géante pour sauver la machine d'un navire échoué."}, ;
  {id = "zola-1885", titre = "Germinal", auteur = "Émile Zola", annee = 1885, genre = "roman", pages = 590, ;
   resume = "Étienne Lantier arrive dans un bassin minier du Nord et mène la grève des mineurs contre la compagnie, dans la faim et la violence."}, ;
  {id = "zola-1877", titre = "L'Assommoir", auteur = "Émile Zola", annee = 1877, genre = "roman", pages = 570, ;
   resume = "La blanchisseuse Gervaise s'installe dans un quartier ouvrier de Paris ; l'alcool ruine peu à peu son foyer et son commerce."}, ;
  {id = "zola-1883", titre = "Au Bonheur des Dames", auteur = "Émile Zola", annee = 1883, genre = "roman", pages = 520, ;
   resume = "Denise, jeune vendeuse, découvre un grand magasin parisien qui écrase les petits commerces du quartier."}, ;
  {id = "balzac-1835", titre = "Le Père Goriot", auteur = "Honoré de Balzac", annee = 1835, genre = "roman", pages = 360, ;
   resume = "Dans une pension parisienne, l'étudiant Rastignac observe le vieux Goriot se ruiner pour ses filles et apprend les règles cruelles de la société."}, ;
  {id = "balzac-1833", titre = "Eugénie Grandet", auteur = "Honoré de Balzac", annee = 1833, genre = "roman", pages = 250, ;
   resume = "À Saumur, la fille d'un tonnelier avare s'éprend de son cousin ruiné ; l'or du père pèse sur toute la maison."}, ;
  {id = "flaubert-1857", titre = "Madame Bovary", auteur = "Gustave Flaubert", annee = 1857, genre = "roman", pages = 480, ;
   resume = "Emma, épouse d'un médecin de campagne normand, rêve d'une vie romanesque et s'endette pour ses amours."}, ;
  {id = "flaubert-1869", titre = "L'Éducation sentimentale", auteur = "Gustave Flaubert", annee = 1869, genre = "roman", pages = 600, ;
   resume = "Frédéric Moreau, jeune provincial à Paris, aime toute sa vie Madame Arnoux pendant que la révolution de 1848 éclate."}, ;
  {id = "stendhal-1830", titre = "Le Rouge et le Noir", auteur = "Stendhal", annee = 1830, genre = "roman", pages = 570, ;
   resume = "Julien Sorel, fils de charpentier ambitieux, gravit les échelons de la société de la Restauration par l'Église et l'amour."}, ;
  {id = "dumas-1844", titre = "Les Trois Mousquetaires", auteur = "Alexandre Dumas", annee = 1844, genre = "aventure", pages = 860, ;
   resume = "Le Gascon d'Artagnan rejoint Athos, Porthos et Aramis au service du roi contre les intrigues du cardinal de Richelieu et de Milady."}, ;
  {id = "dumas-1844b", titre = "Le Comte de Monte-Cristo", auteur = "Alexandre Dumas", annee = 1844, genre = "aventure", pages = 1500, ;
   resume = "Emprisonné à tort au château d'If, le marin Edmond Dantès s'évade, découvre un trésor et prépare sa vengeance."}, ;
  {id = "verne-1870", titre = "Vingt mille lieues sous les mers", auteur = "Jules Verne", annee = 1870, genre = "aventure", pages = 620, ;
   resume = "Le professeur Aronnax est retenu à bord du Nautilus, le sous-marin du mystérieux capitaine Nemo, pour un voyage au fond des océans."}, ;
  {id = "verne-1873", titre = "Le Tour du monde en quatre-vingts jours", auteur = "Jules Verne", annee = 1873, genre = "aventure", pages = 320, ;
   resume = "Sur un pari, le gentleman Phileas Fogg et son domestique Passepartout font le tour du monde en train et en paquebot."}, ;
  {id = "verne-1864", titre = "Voyage au centre de la Terre", auteur = "Jules Verne", annee = 1864, genre = "aventure", pages = 300, ;
   resume = "Le professeur Lidenbrock et son neveu descendent dans un volcan islandais et découvrent un monde souterrain."}, ;
  {id = "maupassant-1883", titre = "Une vie", auteur = "Guy de Maupassant", annee = 1883, genre = "roman", pages = 300, ;
   resume = "Jeanne, jeune noble normande, voit ses illusions de bonheur s'effacer au fil d'un mariage décevant."}, ;
  {id = "maupassant-1885", titre = "Bel-Ami", auteur = "Guy de Maupassant", annee = 1885, genre = "roman", pages = 420, ;
   resume = "Georges Duroy, séducteur sans scrupules, fait carrière dans le journalisme parisien grâce aux femmes."}, ;
  {id = "baudelaire-1857", titre = "Les Fleurs du mal", auteur = "Charles Baudelaire", annee = 1857, genre = "poésie", pages = 260, ;
   resume = "Recueil de poèmes sur le spleen, l'idéal, la ville moderne et la beauté qui naît du mal."}, ;
  {id = "rimbaud-1873", titre = "Une saison en enfer", auteur = "Arthur Rimbaud", annee = 1873, genre = "poésie", pages = 60, ;
   resume = "Récit en prose poétique d'une crise intérieure, entre révolte, hallucinations et adieu à la littérature."}, ;
  {id = "moliere-1664", titre = "Le Tartuffe", auteur = "Molière", annee = 1664, genre = "théâtre", pages = 120, ;
   resume = "Orgon accueille chez lui un faux dévot hypocrite qui manque de lui prendre sa fille, sa femme et sa maison."}, ;
  {id = "racine-1677", titre = "Phèdre", auteur = "Jean Racine", annee = 1677, genre = "théâtre", pages = 90, ;
   resume = "Phèdre, épouse de Thésée, brûle d'une passion coupable pour son beau-fils Hippolyte ; la tragédie mène à la mort."}, ;
  {id = "voltaire-1759", titre = "Candide", auteur = "Voltaire", annee = 1759, genre = "conte", pages = 150, ;
   resume = "Le naïf Candide parcourt un monde plein de guerres et de catastrophes en répétant que tout est au mieux."}, ;
  {id = "proust-1913", titre = "Du côté de chez Swann", auteur = "Marcel Proust", annee = 1913, genre = "roman", pages = 520, ;
   resume = "Une madeleine trempée dans le thé fait renaître les souvenirs d'enfance à Combray et l'amour de Swann pour Odette."} }
