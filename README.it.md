# SteamDeck-Win11-Builder (italiano)

🇬🇧 [English README](README.md)

Kit che trasforma l'ISO ufficiale di Windows 11 in una versione alleggerita e già pronta per lo Steam Deck OLED: driver Valve inclusi, app inutili rimosse, installazione quasi automatica e configurazione al primo avvio.

## Cosa ti serve

- Un PC con Windows 10 o 11 e almeno 25 GB liberi su C:
- Una chiavetta USB da almeno 16 GB (USB-C, oppure con adattatore o hub)
- Circa 35 GB liberi (7 per l'ISO di Windows, che il kit scarica da solo, più lo spazio di lavoro)
- I driver Valve per Steam Deck **OLED**: il kit ti apre la pagina giusta, tu li scarichi in una cartella (anche in .zip)
- Rufus (https://rufus.ie)
- Consigliato: un hub USB-C con tastiera e mouse. Il touch funziona, ma l'installazione di Windows appare in verticale

## Prima di cancellare SteamOS

1. Aggiorna SteamOS all'ultima versione stabile: installa anche il BIOS più recente, che serve al Bluetooth sotto Windows.
2. Metti al sicuro i salvataggi che non sono nel cloud di Steam (emulatori, giochi non Steam).
3. Per tornare a SteamOS in futuro basta l'immagine di ripristino ufficiale di Valve.

## 1. Crea l'ISO (sul PC)

1. Scarica questo repository (pulsante verde **Code** → **Download ZIP**) ed estrailo.
2. Doppio clic su **Build-ISO.cmd** e conferma la richiesta di amministratore.
3. Rispondi **S** quando chiede se scaricare l'ISO: la prende dai server Microsoft, nella versione più recente e nella stessa lingua del tuo PC. Se il download automatico è bloccato, ti apre la pagina Microsoft per scaricarla a mano. Se l'ISO ce l'hai già, rispondi **n** e sceglila.
4. Si apre la pagina Valve: scarica i driver per Steam Deck OLED, premi INVIO e scegli la cartella dove li hai salvati.
5. Aspetta 30-60 minuti più il download. Alla fine trovi `Win11-SteamDeckOLED.iso` (e il log) nella cartella del kit. L'ISO originale resta in `Download`, così se rilanci non la riscarica.

Opzioni avanzate, lanciando lo script da Windows PowerShell come amministratore:

| Opzione | Effetto |
|---|---|
| `-IsoLanguage Italian` | Lingua dell'ISO scaricata (default: quella del PC) |
| `-UserName Marco` | Nome dell'account locale (default `Deck`) |
| `-Password "..."` | Password dell'account (default nessuna) |
| `-Edition Home` | Edizione da tenere (default `Pro`) |
| `-Locale`, `-KeyboardLayout`, `-TimeZone` | Impostazioni regionali (default: quelle del PC) |
| `-RemoveXbox` | Toglie anche app Xbox e Game Bar |
| `-AllowWindowsUpdateDrivers` | Lascia che Windows Update aggiorni i driver |
| `-SkipComponentCleanup` | Più veloce, ISO un po' più grande |
| `-KeepVBS` | Lascia attiva l'Integrità della memoria (vedi sotto) |
| `-CompactOS` | Comprime i file di Windows: circa 2-3 GB in meno sul disco |

## 2. Prepara la chiavetta

In Rufus scegli l'ISO creata, schema **GPT**, destinazione **UEFI**. Quando Rufus propone le personalizzazioni di Windows (account locale, requisiti, ecc.) **togli tutte le spunte**: il kit le fa già.

## 3. Installa sul Deck

1. Deck spento e chiavetta collegata: tieni premuto **Volume giù** e premi **Accensione**, poi scegli la chiavetta nel Boot Manager.
2. La schermata di installazione è in verticale: è normale.
3. Alla scelta del disco elimina **tutte** le partizioni del disco interno (quello da 512 GB o 1 TB, di solito "Unità 0"). Non toccare la chiavetta né la microSD. Seleziona lo spazio non allocato e premi Avanti.
4. Se chiede il codice Product Key scegli **"Non ho un codice Product Key"**. Windows si attiva con la tua licenza digitale, se ce l'hai.
5. Quando lo schermo diventa nero per il primo riavvio, scollega la chiavetta.
6. Il resto è automatico: niente account Microsoft, niente domande sulla privacy.

## 4. Primo avvio

Si apre da solo **Steam Deck Setup**, che:

- esegue gli installer dei driver Valve (se uno chiede di riavviare, scegli "più tardi")
- mette lo schermo in orizzontale e ti chiede se è dritto
- imposta lo schermo a 90 Hz
- ti fa collegare al Wi-Fi
- installa **Steam** e **Handheld Companion** (controlli come pad Xbox, TDP, overlay)
- propone di installare **Lossless Scaling** per la frame generation (vedi sotto)
- propone di avviare Steam in **Big Picture** a ogni accensione

Puoi rilanciarlo dall'icona sul desktop: i passaggi già fatti vengono saltati. Log in `C:\DeckSetup`.

## Cosa cambia rispetto a Windows standard

**App rimosse:** Copilot, Teams, nuovo Outlook, Posta, Clipchamp, Notizie, Meteo, Solitario, To Do, Sticky Notes, Feedback Hub, Mappe, Collegamento al telefono, Family, Assistenza rapida, Dev Home, Power Automate, Fotocamera, Widget, OneDrive.

**Componenti rimossi:** Recall, modalità Internet Explorer, Windows Hello viso, Windows Media Player classico, Paint classico, WordPad, PowerShell ISE, Registrazione azioni utente, Fax e scanner, riconoscimento della scrittura a penna e delle formule, sfondi aggiuntivi, PowerShell 2.0, Cartelle di lavoro, servizi XPS.

**Resta:** Microsoft Store, winget, Edge (serve a molti launcher), Foto, Paint, Blocco note, Calcolatrice, Cattura, Terminale, Lettore multimediale, app Xbox e Game Bar, stampa normale.

**Prestazioni e batteria:** Integrità della memoria e VBS spente, servizio di telemetria e servizi inutili disattivati, Edge non resta caricato in background, aggiornamenti senza upload verso altri PC, niente registrazione di gioco in background, ibernazione spenta, niente spazio riservato, niente crittografia automatica del disco.

**Esperienza da console:** niente schermata di blocco, gli swipe dai bordi dello schermo non aprono pannelli mentre giochi, niente riavvii forzati per gli aggiornamenti mentre sei connesso, niente popup dei Tasti permanenti, barra delle applicazioni compatta, tastiera touch automatica.

**Privacy:** telemetria al minimo, niente app sponsorizzate, suggerimenti o pubblicità nel menu Start, Copilot spento, Windows Update attivo ma senza sostituire i driver Valve.

### Integrità della memoria (VBS)

Su Windows 11 è attiva di default e su una APU come quella del Deck costa qualche punto percentuale di FPS. Il kit la spegne: guadagni prestazioni, ma perdi uno strato di protezione contro i driver malevoli. Se il Deck lo usi anche per lavoro o preferisci la sicurezza, crea l'ISO con `-KeepVBS`.

## Frame generation con Lossless Scaling (al posto di Decky)

Il plugin Decky **LSFG-VK** è un adattamento per Linux dell'app Windows **Lossless Scaling**, e anche su SteamOS richiede di averla comprata su Steam. Su Windows non serve convertire niente: usi direttamente l'originale, sempre aggiornato e compatibile con DirectX, Vulkan e OpenGL.

Decky Loader su Windows esiste ma il progetto lo dichiara non supportato e instabile, e la maggior parte dei plugin è scritta per SteamOS. Il menu rapido di **Handheld Companion** copre già TDP, profili e controlli.

**Configurazione consigliata sul Deck OLED (schermo a 90 Hz):**

1. Installa Lossless Scaling da Steam (lo script del primo avvio te lo propone).
2. Nel gioco imposta **Finestra senza bordi**: lo schermo intero esclusivo non è supportato.
3. Blocca il frame rate del gioco a **45 FPS** (metà di 90), dalle opzioni del gioco o con RivaTuner (RTSS). Una base stabile conta più di una base alta.
4. In Lossless Scaling: frame generation **LSFG**, moltiplicatore **X2** (45 → 90 FPS). In alternativa la modalità **adattiva** con obiettivo 90.
5. Se il gioco perde fluidità, abbassa **Flow scale** o attiva **Performance mode**: la frame generation usa la stessa GPU del gioco, quindi serve margine.
6. Se l'immagine non viene catturata, prova l'altra API di cattura (WGC o DXGI).
7. Salva un **profilo per gioco** in Lossless Scaling.

**Attivazione con un tasto:** la scorciatoia di Lossless Scaling è **Ctrl+Alt+S**. Assegnala a un tasto posteriore (L4/R4): nei giochi Steam dal layout di Steam Input (comando aggiuntivo sul tasto), negli altri da Handheld Companion. Così hai l'equivalente del menu del plugin.

**Limiti:** la frame generation aumenta la fluidità, non la reattività. Aggiunge un po' di ritardo ai comandi e rende male se la base scende sotto i 40 FPS. Per i giochi competitivi meglio lasciarla spenta.

## Da sapere

- Gli script mostrano i messaggi in inglese.

- Valve non offre supporto tecnico per Windows sul Deck.
- Quando Valve pubblica driver nuovi, scaricali e installali a mano (Windows Update non lo fa, per scelta).
- Per i giochi fuori da Steam usa Handheld Companion per far vedere i controlli come un pad Xbox.
- Il kit è stato provato su una Steam Deck OLED con Windows 11 25H2 e i driver Valve di agosto 2024. Con altre combinazioni di ISO e driver potrebbe comportarsi diversamente: in caso di errore, il log accanto all'ISO dice dove si è fermato.

## Problemi noti e soluzioni

- **"Dispositivi sconosciuti" in Gestione dispositivi** (VLV0100, PRP0001, ANX7580, AMDI8821, controller di crittografia PCI): sono componenti senza driver Windows ufficiale. Sono normali e non influiscono su gioco, audio, Wi-Fi o controlli.
- **Errore DirectX `DXGI_ERROR_INVALID_CALL` all'avvio di un gioco** (per esempio EA FC 27): il gioco prova lo schermo intero esclusivo. Mettilo in **finestra senza bordi**. Per FC 27, in `%LOCALAPPDATA%\EA SPORTS FC 27\fcsetup.ini` imposta `FULLSCREEN = 0`, `WINDOWED_BORDERLESS = 1` e `RESOLUTIONHEIGHT = 800`.
- **Stuttering:** schermo a 90 Hz e gioco bloccato a 45 FPS (V-Sync 50%). Se serve, porta la memoria video a 4 GB dal BIOS: Volume su + Accensione → Setup Utility → Advanced → UMA Frame Buffer Size → 4G.
- **Giochi che richiedono il Secure Boot** (Battlefield 6, Call of Duty Black Ops 7, Valorant, tornei di Fortnite): non funzionano, perché il Deck non offre il Secure Boot per Windows.
- **La creazione si è fermata dopo aver finito l'immagine** (per esempio a "Creating the ISO"): rilancia Build-ISO.cmd. Trova il lavoro già fatto in `C:\DeckBuild` e propone di creare solo l'ISO, in un paio di minuti invece di un'ora.
