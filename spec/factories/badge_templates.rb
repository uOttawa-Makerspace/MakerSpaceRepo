FactoryBot.define do
  factory :badge_template do
    trait :'3d_printing' do
      id { 1 }
      acclaim_template_id { '7fc521fa-00s4-4ase-a7f6-902802262e3b' }
      badge_description { 'The badge earner has demonstrated their ability to understand and apply the basic rules for 3D printing an object, how to slice a 3D model and start a print on the machine. || Le porteur a démontré sa capacité à comprendre et à appliquer les règles de base lors de l’impression 3D d’un objet; comment trancher son modèle et l’utilisation de l’imprimante afin de réaliser son objet.' }
      badge_name { 'Beginner - 3D printing || Débutant - Impression 3D' }
      image_url { 'https://images.youracclaim.com/images/1836ef76-cb9a-410b-bcea-97dcd0f2c3d4/1.png' }
    end

    trait :laser_cutting do
      id { 2 }
      acclaim_template_id { '37f37418-3be4-448a-b012-a575f9d06a71' }
      badge_description { 'The badge earner has demonstrated the basic skills needed for 2D modelling and to operate a laser cutter. || Le porteur de ce badge a démontré les compétences de base nécessaires pour la modélisation 2D et à l\'utilisation d\'une machine laser.' }
      badge_name { 'Beginner Laser cutting || Beginner - Laser cutting' }
      image_url { 'https://images.youracclaim.com/images/4561c296-f2dc-4b1e-b17b-19c4bb561a9e/4.png' }
    end

    trait :arduino do
      acclaim_template_id { 'd36b6e25-732b-43b1-a40e-b254207c734d' }
      badge_description { 'The earner has developed the applied skills of writing simple control logic commands that will help control a variety of inputs and outputs connected to an Arduino Uno microcontroller. || Le porteur a développé les compétences nécessaires afin d’écrire des commandes logiques de contrôle simples leur permettant de contrôler diverses entrées et sorties connectées à un microcontrôleur Arduino.' }
      badge_name { 'Beginner - Arduino || Débutant - Arduino' }
      image_url { 'https://images.youracclaim.com/images/1c6b8766-cf74-4314-b5af-bce55cbbd863/3.png' }
    end
  end
end






