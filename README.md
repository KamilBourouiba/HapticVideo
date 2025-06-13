# HAPTICKAnalyzer

Un package Swift pour analyser les vidéos et générer des événements haptiques basés sur l'audio.

## Fonctionnalités

- Extraction audio depuis les vidéos
- Analyse des caractéristiques audio (RMS, fréquences, rolloff spectral, bande passante)
- Génération d'événements haptiques basés sur l'analyse
- Sauvegarde des données au format JSON

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/KamilBourouiba/HAPTICKAnalyzer.git", from: "1.0.0")
]
```

## Utilisation

```swift
import HAPTICKAnalyzer

let analyzer = HAPTICKAnalyzer(fps: 60)

// Utilisation asynchrone
Task {
    do {
        let videoURL = URL(fileURLWithPath: "chemin/vers/votre/video.mp4")
        let jsonURL = try await analyzer.hapticVideo(videoURL)
        print("Fichier JSON généré : \(jsonURL)")
    } catch {
        print("Erreur : \(error)")
    }
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

Copyright Bourouiba Mohamed Kamil 2025.  
All rights reserved.

This code is published for reference only.  
Do not use, copy, modify, or distribute without explicit permission. 