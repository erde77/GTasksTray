# GTasksTray

Polska aplikacja na macOS, która pokazuje liczbę otwartych zadań Google Tasks w pasku menu. Kliknij ikonę, by przejrzeć zadania ze wszystkich list, zobaczyć notatki, daty i linki do źródeł, oznaczyć zadanie jako ukończone lub dodać nowe. Sekcja **Ukończone** pokazuje pięć ostatnich zadań, a przycisk **Pokaż więcej** odsłania starsze. Po ukończeniu zadania zobaczysz animację i usłyszysz krótki dźwięk, który możesz wyłączyć w menu aplikacji.

Przycisk na dole panelu przełącza na istniejącą kartę Google Tasks w Chrome lub otwiera nową. Przy pierwszej próbie macOS może poprosić o zgodę na Automatyzację Chrome. Bez tej zgody przycisk otworzy nową kartę.

## Uruchomienie

Potrzebujesz macOS 13 lub nowszego, narzędzi Xcode ze Swiftem 6 oraz Google Chrome do otwierania widoku webowego. W katalogu projektu uruchom:

```sh
./scripts/build-app.sh
open dist/GTasksTray.app
```

Aplikację znajdziesz w górnym pasku menu. Gotowy pakiet `dist/GTasksTray.app` możesz też przenieść do folderu Aplikacje.

## Pierwsze połączenie z kontem Google

1. Wybierz lub utwórz projekt w [Google Cloud Console](https://console.cloud.google.com/) i włącz [Google Tasks API](https://console.cloud.google.com/apis/library/tasks.googleapis.com).
2. W [Google Auth Platform](https://console.cloud.google.com/auth/overview) skonfiguruj ekran zgody. Dla prywatnego konta Google wybierz **External** i w sekcji **Audience** dodaj swój adres jako użytkownika testowego. W **Data Access** dodaj zakres `https://www.googleapis.com/auth/tasks`.
3. W sekcji **Clients** utwórz klienta OAuth typu **Desktop app** i pobierz jego plik JSON.
4. Kliknij ikonę GTasksTray, wybierz **Wybierz plik OAuth…** i wskaż pobrany plik. Kliknij **Zaloguj się przez Google**, wybierz konto w przeglądarce i zaakceptuj dostęp do zadań.
5. Wróć do panelu. Aplikacja odświeża dane w tle co 90 sekund. Możesz też wymusić odświeżenie przyciskiem w nagłówku.

Aplikacja przechowuje konfigurację OAuth i token odświeżania w Pęku kluczy macOS. W trybie **External → Testing** Google wygasza zgodę po siedmiu dniach. Aplikacja poprosi wtedy o ponowne logowanie. [Dokumentacja Google](https://support.google.com/cloud/answer/15549945)

Przy kilku kontach Google wybierz w Chrome to samo konto, którego używasz w GTasksTray. Google Tasks API udostępnia dzień zaplanowania zadania. Godziny, cykle i dodatkowe terminy ustawisz w pełnym widoku webowym. [Dokumentacja Google Tasks API](https://developers.google.com/workspace/tasks/reference/rest/v1/tasks)

## Testy

```sh
swift test
```

Testy sprawdzają stronicowanie, liczenie otwartych zadań, dodawanie i kończenie zadań na danych testowych, zapis daty oraz odbiór odpowiedzi OAuth na lokalnym adresie.
