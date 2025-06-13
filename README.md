# HapticVideo

Un package Swift pour générer des données haptiques à partir de fichiers vidéo.

## Installation

Ajoutez le package à votre projet Xcode en utilisant Swift Package Manager :

```swift
dependencies: [
    .package(url: "https://github.com/KamilBourouiba/HapticVideo.git", from: "1.0.0")
]
```

## Utilisation

```swift
import HapticVideo

// Créer une instance de VideoHaptic
let hapticGenerator = VideoHaptic(target: "chemin/vers/votre/video.mp4")

// Générer les données haptiques
Task {
    do {
        let hapticData = try await hapticGenerator.generateHapticData()
        // Utiliser les données haptiques...
        print("Nombre d'événements haptiques : \(hapticData.hapticEvents.count)")
    } catch {
        print("Erreur : \(error)")
    }
}
```

## Fonctionnalités

- Analyse audio en temps réel
- Génération d'événements haptiques basés sur l'intensité et la netteté du son
- Support pour différents types de retours haptiques (heavy, medium, light, soft)
- Optimisé pour les performances avec Accelerate framework

## Configuration

Vous pouvez personnaliser le FPS des événements haptiques lors de l'initialisation :

```swift
let hapticGenerator = VideoHaptic(target: "video.mp4", fps: 120)
```

## Structure des données

Les données haptiques sont structurées comme suit :

```swift
struct HapticData {
    let metadata: Metadata
    let hapticEvents: [HapticEvent]
}

struct HapticEvent {
    let time: Double
    let intensity: Double
    let sharpness: Double
    let type: String
}
```

## Types d'événements haptiques

- `heavy` : Retour haptique fort
- `medium` : Retour haptique moyen
- `light` : Retour haptique léger
- `soft` : Retour haptique doux

## Dépendances

- FFmpegKit
- AudioKit

## Licence

Copyright © 2024 Bourouiba Mohamed Kamil. Tous droits réservés.

Ce projet est protégé par les lois sur le droit d'auteur. Toute reproduction, distribution ou modification non autorisée est strictement interdite. 