# Project-Scoped Rules: Ride Analytics App

This project is a premium offline-first motorcycle ride analytics application built using Flutter.

## Core Directives

1. **Architecture**: Adhere strictly to Clean Architecture (Presentation, Domain, Data layers). Keep UI widgets entirely free of business logic.
2. **State Management**: Use Riverpod for state management (unless otherwise clarified by the user).
3. **Storage**: Rely on Isar Database for offline-first persistence of all ride data. Avoid cloud or backend dependencies.
4. **Performance**: Every UI change must prioritize maintaining 60 FPS. Ensure heavy processing tasks (e.g., GPS point ingestion) run on isolates or are highly optimized to avoid blocking the main UI thread.
5. **Design Aesthetics**: Focus on a "luxury automotive dashboard" feel. Utilize dark-first themes, minimalist layouts, glassmorphism/translucency, and large touch targets designed for glove-wearing riders. Use high-contrast and a single bold accent color.
6. **Code Standards**: Adhere to SOLID principles, use immutable models (Freezed), write small reusable widgets, and inject dependencies. Ensure all models are generated with `json_serializable`.

## Reference Stack
- **Framework**: Flutter
- **Location**: `geolocator`, `permission_handler`
- **Routing**: GoRouter
- **Mapping**: `google_maps_flutter`
- **Database**: Isar

Always verify any implemented functionality respects the offline-first requirements and performs well on mobile devices.
