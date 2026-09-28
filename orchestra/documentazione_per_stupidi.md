# Orchestra per stupidi 🎻

*Come far pensare Claude e far lavorare opencode, in qualsiasi progetto.*

---

## 1. L'idea in 30 secondi

Hai due "cervelli":

| Chi | Cosa fa | Costo |
|---|---|---|
| **Claude** (il capo) | Capisce cosa vuoi, progetta, scrive le istruzioni precise, controlla il lavoro | Caro → lo usiamo poco |
| **opencode** (l'operaio) | Scrive il codice, lancia i test, corregge gli errori finché va | Economico o gratis → lo usiamo tanto |

Il flusso è sempre lo stesso:

```
Tu chiedi una cosa
   │
   ▼
Claude scrive la SPEC (cosa costruire) e un BRIEF per ogni fase (istruzioni precise)
   │
   ▼
opencode esegue il brief: codice + test + debug, poi scrive un REPORT
   │
   ▼
Claude fa la REVIEW: legge il codice, prova i casi strani
   │
   ├── va bene → ACCETTATO, si passa alla fase dopo
   └── non va  → UNA sola lista di correzioni a opencode, poi ricontrolla
```

È la stessa idea di [astra-flash-orchestrator](https://github.com/ethanplusai/astra-flash-orchestrator),
ma con Claude Code al posto di Codex e opencode come operaio.

---

## 2. Cosa ti serve (una volta sola)

1. **Claude Code** installato (ce l'hai già).
2. **opencode** installato e funzionante. Verifica:
   ```bash
   opencode --version
   opencode run -m opencode/big-pickle "Rispondi solo: PONG"
   ```
   Se risponde `PONG`, sei a posto.
3. **Python 3** (per lo script `delegate.py`).
4. **git** (serve a Claude per vedere cosa ha cambiato l'operaio).

### Quale modello usa l'operaio?

Di default `opencode/big-pickle` (gratis). Per vedere tutti i modelli:
```bash
opencode models
```
Modelli gratuiti provati e funzionanti: `opencode/big-pickle`,
`opencode/mimo-v2.6-flash-free`, `opencode/nemotron-3-ultra-free`.

Per cambiare modello **per sempre** (aggiungilo a `~/.bashrc`):
```bash
export ORCHESTRA_WORKER_MODEL=opencode/deepseek-v4.1-flash
```
⚠️ I modelli a pagamento di OpenCode Zen richiedono credito sull'account,
altrimenti ricevi `Insufficient account funds`. In alternativa colleghi un tuo
provider con `opencode auth login`.

---

## 3. Installarla in un altro progetto (il modo facile)

Da questa cartella (`claude-orchestra`) lancia:

```bash
orchestra/install.sh /percorso/del/tuo/progetto
```

Fatto. Lo script copia:

| File | A cosa serve |
|---|---|
| `orchestra/delegate.py` | Il "telefono" con cui Claude chiama opencode |
| `orchestra/watch.py` | Il "citofono" per vedere a che punto è l'operaio |
| `orchestra/templates/` | I moduli da compilare (brief e report) |
| `.claude/skills/orchestra/SKILL.md` | Le regole di Claude-capo |
| `AGENTS.md` | Le regole dell'operaio (opencode lo legge da solo) |
| `CLAUDE.md` | Dice a Claude di usare l'orchestra |

Tranquillo:
- se il progetto ha **già** `AGENTS.md` o `CLAUDE.md`, lo script **aggiunge** una sezione (tra `<!-- orchestra -->` e `<!-- /orchestra -->`), non cancella niente del tuo;
- puoi rilanciarlo quante volte vuoi: non duplica nulla e aggiorna solo la sua sezione.

Se il progetto non è un repository git:
```bash
cd /percorso/del/tuo/progetto && git init
```

### Il modo manuale (se lo script non ti piace)
Copia a mano i 5 elementi della tabella sopra nelle stesse posizioni. Fine.

---

## 4. Usarla tutti i giorni

1. Apri Claude Code nel progetto:
   ```bash
   cd /percorso/del/tuo/progetto && claude
   ```
2. Chiedi quello che vuoi, normalmente. Per essere sicuro che usi l'orchestra:
   > usa l'orchestra: aggiungi l'export in PDF delle fatture

   oppure digita `/orchestra` seguito dalla richiesta.
3. Claude:
   - scrive `docs/agent-work/<nome-funzionalità>/spec.md`
   - scrive un brief per fase: `T1.md`, `T2.md`, …
   - lancia opencode e **aspetta** (non lo disturba)
   - fa la review e ti dice cosa è stato accettato e cosa è stato corretto
4. Tu guardi il risultato e, se ti piace, fai il commit (Claude non committa da solo).

### Cosa NON vale la pena delegare
Domande, un typo, una modifica di 3 righe: Claude le fa direttamente.
Delegare costa più tempo che farle. L'orchestra serve per lavori **veri**
(più file, test, funzionalità nuove, refactoring).

---

## 4bis. "A che punto è?" — monitorare l'operaio

Mentre opencode lavora hai **tre modi** per vedere cosa sta facendo.

### a) Lo vedi in chat, senza fare niente
Appena Claude lancia un task, attacca un "monitor". In chat ti arrivano
solo le tappe importanti, così:

```
▶ watching T4 [opencode/big-pickle]
0:08  $ python -m unittest discover -s tests  → exit 0  [Ran 78 tests · OK]
0:12  ☑ 1/5 steps · now: Run every CLI command and capture real output
1:05  ✎ created expenses/README.md
1:10  ✎ edited expenses/README.md
1:26  ✎ created docs/agent-work/budgets/T4.report.md
1:30  ☑ 5/5 steps
■ finished: exit 0 · 5/5 steps · files 2 · tests Ran 78 tests · OK
```

Leggenda: `☑` = avanzamento della lista di cose da fare, `✎` = file scritto,
`$` = comando lanciato (con esito dei test), `✖` = errore,
`⚠` = l'operaio è fermo da più di 5 minuti.

### b) Chiedi a Claude
Scrivi semplicemente *"a che punto è?"*. Claude lancia `orchestra/watch.py --status`
e ti risponde con una fotografia:

```
task:     T4  [opencode/big-pickle]
state:    running   elapsed 1m10s
progress: 1/5 steps · now: Write expenses/README.md
            [x] Explore codebase, spec, tests, examples
            [>] Write expenses/README.md
            [ ] Re-run tests
            ...
files:    expenses/README.md
tests:    Ran 78 tests · OK (exit 0)
tokens:   in 34047  out 14510  cost $0.0000
```

### c) Lo guardi tu in diretta, in un altro terminale
```bash
cd /percorso/del/tuo/progetto
orchestra/watch.py
```
Mostra **tutto** in tempo reale (anche i file letti e i messaggi dell'operaio,
in grigio), e si chiude da solo quando l'operaio finisce.
Senza argomenti guarda il task più recente; puoi anche passargli un log preciso:
`orchestra/watch.py docs/agent-work/mia-feature/T2.<data>.jsonl`.

Funziona anche **dopo**: `orchestra/watch.py --status docs/agent-work/.../T1.<data>.jsonl`
ti riassume un task già finito.

> Perché la percentuale funzioni, l'operaio deve tenere una lista di cose da fare:
> è una regola scritta in `AGENTS.md`. Se vedi `no todo list yet` a lungo,
> l'operaio la sta ignorando (capita con i modelli più deboli): il resto del
> monitoraggio (file, comandi, test) funziona comunque.

---

## 4ter. Immagini: icone, sprite, sfondi generati da soli

Quando un lavoro ha bisogno di un'immagine, **né Claude né l'operaio te la chiedono**:
la generano con Stable Diffusion (su Cloudflare) e la salvano nella cartella
degli asset del progetto.

```
Claude / opencode ──► generate_asset (orchestra/asset_mcp.py, gira sul TUO pc)
                           │  POST /generate + token segreto
                           ▼
                     Worker Cloudflare "orchestra-assets" (SDXL Lightning)
                           │  JPEG
                           ▼
       (se serve trasparenza) scontorno locale con rembg → PNG trasparente
                           ▼
                salvato in public/assets/… del progetto
```

### Cosa è già configurato (una volta sola, vale per tutti i progetti)

| Pezzo | Dove |
|---|---|
| Worker Cloudflare | `https://orchestra-assets.lucatarik.workers.dev` (codice in `asset-worker/`) |
| URL + token segreto | `~/.config/orchestra/assets.env` (permessi 600, **non** va mai in git) |
| Tool MCP per Claude | registrato a livello utente: `claude mcp get orchestra-assets` |
| rembg (scontorno) | `~/.local/share/orchestra/rembg-venv` (≈ 600 MB + modello 179 MB in `~/.u2net`) |

Controllo veloce che tutto funzioni:
```bash
orchestra/asset_mcp.py check
```

### Usarlo

Non devi fare niente: chiedi "fai una landing page per una scuola di musica"
e Claude genera l'immagine di copertina da solo. Se vuoi farlo a mano:

```bash
# immagine normale (il modello restituisce JPEG)
orchestra/asset_mcp.py generate "cozy music school interior, warm light, photo" public/assets/hero.jpg --width 1344 --height 768

# icona/sprite con sfondo TRASPARENTE (esce sempre .png)
orchestra/asset_mcp.py generate "flat vector violin icon, centered, plain white background" public/assets/violin.png --remove-bg --trim
```

Regole utili:
- **Scrivi i prompt in inglese** e descrivi stile, colori, inquadratura.
- **Niente testo nelle immagini**: il modello scrive male le parole. Il testo va in HTML/CSS.
- Per la trasparenza chiedi *"isolated on a plain solid white background"* e usa `--remove-bg`.
  Se lo scontorno viene male prova `--bg-model u2net` o `--bg-model isnet-anime` (per disegni/cartoni).
- Con FLUX le immagini seguono il prompt; se una non va, rigenera solo quella.
- Se chiedi `.png` ma il modello dà JPEG, il file viene salvato come `.jpg` e il comando
  ti dice il percorso giusto da usare.

### Risparmiare chiamate e quota (importante)

Il modello predefinito è **FLUX.2 klein 4B**: segue bene i prompt (niente più pattern o badge a caso)
e costa circa **104 "neuroni" per immagine 1024×1024**. Cloudflare regala **10.000 neuroni al giorno
per tutto l'account**: circa 90 immagini. Finiti quelli **si ferma tutto fino alle 02:00 (ora italiana)**,
anche il modello gratuito.

| Ti serve | Usa | Costo |
|---|---|---|
| Tante icone, anche con soggetti precisi (sole, palloncino, …) | `generate_icon_sheet` con `items` / `asset_mcp.py sheet "stile" cartella --item sole --item palloncino …` | **1 generazione** per fino a 24 icone, ritagliate e salvate da sole |
| 2+ immagini con dimensioni/composizioni diverse | `generate_assets` / `asset_mcp.py batch file.json` | 1 chiamata, 1 anteprima |
| Un'immagine sola (sfondo, hero) | `generate_asset` / `asset_mcp.py generate` | 1 |

Con i fogli "nominati" FLUX a volte salta o ripete un soggetto: Claude guarda l'anteprima **una volta**,
rinomina i file e rigenera solo quelli mancanti.

Ogni risultato termina con `today ~X/10000 neurons`: il bridge tiene un contatore (in
`~/.local/share/orchestra/usage.json`) e **si ferma da solo al 90%** prima di chiamare Cloudflare.
Se la quota finisce davvero, i tool rispondono "do not retry" e Claude non spreca altri tentativi.

Altri modelli (`image_model` / `--image-model`): `sdxl-lightning` (gratis ma impreciso),
`flux-2-klein-9b` (~13× più caro, veloce, il seed funziona), `phoenix-1.0` (~20× più caro).
Per usarne uno di default: `export ORCHESTRA_IMAGE_MODEL=sdxl-lightning`.

Trasparenza perfetta: chiedi *"solid plain green background"* (magenta se il soggetto è verde) e usa
`--remove-bg`: lo sfondo piatto viene tolto per colore, con bordi netti.

### Rifarlo su un altro PC (o se cancelli tutto)

1. `cd asset-worker && npm install && npx wrangler login && npx wrangler deploy`
   (serve Node ≥ 22: con nvm `nvm use 24`)
2. Crea il token e salvalo in due posti (Cloudflare + file locale):
   ```bash
   TOKEN=$(python3 -c "import secrets;print(secrets.token_urlsafe(32))")
   printf '%s' "$TOKEN" | npx wrangler secret put ASSET_TOKEN
   mkdir -p ~/.config/orchestra && umask 077 && printf 'ASSET_WORKER_URL=<url del worker>\nASSET_WORKER_TOKEN=%s\n' "$TOKEN" > ~/.config/orchestra/assets.env
   ```
3. rembg: `python3 -m venv ~/.local/share/orchestra/rembg-venv && ~/.local/share/orchestra/rembg-venv/bin/pip install "rembg[cpu]"`
4. `claude mcp add orchestra-assets -s user -- python3 /percorso/claude-orchestra/orchestra/asset_mcp.py serve`

### Costi
Il free tier di Workers AI ha un limite giornaliero di "neuroni". Con i default
(4 step, 1024×1024) ogni immagine costa poco; aumentare `num_steps` o le dimensioni
consuma di più. Il token impedisce a sconosciuti di usare la tua quota.

---

## 5. Dove trovo le cose

Tutto il lavoro di una funzionalità sta in `docs/agent-work/<funzionalità>/`:

| File | Cos'è |
|---|---|
| `spec.md` | Il progetto (scritto da Claude) |
| `T1.md`, `T2.md` … | Le istruzioni per ogni fase (scritte da Claude) |
| `T1.report.md` | Cosa ha fatto l'operaio + in fondo il verdetto di Claude |
| `T1.<data>.jsonl` | Il log completo di opencode (per debug, di solito non serve) |
| `T1.fix.<data>.jsonl` | Il log del giro di correzioni |
| `T1.<data>.status.json` | In corso / finito (lo usa `watch.py`) |

---

## 6. Usare `delegate.py` a mano (facoltativo)

Non serve, lo fa Claude. Ma se vuoi lanciare un brief tu (sempre **dalla cartella
principale del progetto**, perché l'operaio lavora nella cartella da cui lo lanci):

```bash
# lancia un brief
orchestra/delegate.py docs/agent-work/mia-feature/T1.md

# con un modello diverso
orchestra/delegate.py docs/agent-work/mia-feature/T1.md --model opencode/mimo-v2.6-flash-free

# manda correzioni alla STESSA sessione dell'operaio ("last" = l'ultima esecuzione di quel brief)
orchestra/delegate.py docs/agent-work/mia-feature/T1.md --session last --message "Correggi: ..."
```

Stampa un riassunto corto: sessione, strumenti usati, token, costo, messaggio finale.

---

## 7. Le regole d'oro (perché funziona)

1. **Claude decide, opencode esegue.** Architettura, sicurezza, formati dei dati
   e API li decide Claude nel brief. L'operaio non inventa contratti.
2. **Brief precisi.** Più il brief è preciso (firme delle funzioni, messaggi di errore esatti,
   comandi di test), meno correzioni servono.
3. **Una fase alla volta.** Se la fase 2 usa il codice della fase 1, la fase 2
   si scrive **dopo** che la fase 1 è stata accettata.
4. **"Fatto" dell'operaio ≠ accettato.** Claude controlla sempre. Nella prova
   l'operaio diceva "31 test passano", ma Claude ha trovato 4 bug che i test non coprivano.
5. **Massimo un giro di correzioni.** Se dopo un giro c'è ancora qualcosa di piccolo,
   Claude lo sistema da sé; se è grosso, ripensa il task.

---

## 8. Problemi comuni

| Sintomo | Soluzione |
|---|---|
| `Insufficient account funds` | Il modello è a pagamento: usa un modello `-free`/`big-pickle` o ricarica il credito |
| `opencode: command not found` | Aggiungi `~/.opencode/bin` al `PATH` |
| L'operaio si blocca / va in timeout | `delegate.py` ha `--timeout` (default 1800 s); spezza il task in fasi più piccole |
| L'operaio ha toccato file che non doveva | Le regole sono in `AGENTS.md` ma **non sono un blocco reale** (gira con `--auto`). Usa git per vedere e annullare: `git status`, `git diff` |
| Claude non usa l'orchestra | Chiedilo esplicitamente ("usa l'orchestra") o usa `/orchestra` |
| Voglio aggiornare l'orchestra in un progetto già installato | Rilancia `install.sh`: script, skill e le sezioni orchestra di `AGENTS.md`/`CLAUDE.md` vengono aggiornati |
| `… is already being worked on` / `session … is still running` | Protezione voluta: non si possono avere due operai sullo stesso brief o sulla stessa sessione (si mescolerebbero conversazione e file). Aspetta la fine (`orchestra/watch.py`) o fermalo |
| L'operaio è fermo e `watch.py --status` mostra `PROVIDER ERROR … Rate limit exceeded` | Il modello gratuito ha finito la quota (succede se più progetti lo usano insieme). `delegate.py` se ne accorge da solo e **riprende la stessa sessione con il modello gratuito successivo** (`big-pickle → nemotron → ling → mimo`). Lista modificabile con `export ORCHESTRA_FALLBACK_MODELS=...` |
| opencode resta muto all'avvio (log vuoto) | Capita: dopo 120 s senza eventi `delegate.py` lo riavvia da solo con il modello successivo (`--startup-timeout`) |
| Non so se l'operaio sta lavorando o è bloccato | `orchestra/watch.py --status` (vedi sezione 4bis); `⚠` = fermo da più di 5 minuti |

⚠️ **Sicurezza:** opencode gira con `--auto`, cioè approva da solo i propri comandi.
Usalo su progetti dove git ti protegge, non su cartelle con segreti o dati importanti non versionati.

---

## 9. Esempio reale: lavoro in più fasi

In questa cartella trovi un esempio completo in `docs/agent-work/budgets/`.
Richiesta: *"aggiungi i budget mensili per categoria al programma delle spese"*.

### Come Claude l'ha divisa

```
spec.md  (Claude)  →  decide formato del file budget, regole di calcolo, messaggi d'errore
   │
   ├─ T2  fase 1: la LOGICA  (expenses/budget.py + test)
   │        contratti: load_budgets(), check(), BudgetStatus
   │        ▼ opencode 68 s → review Claude → ACCETTATO
   │
   └─ T3  fase 2: il COMANDO  (python -m expenses budget …)
            scritto DOPO T2, usando l'API vera di T2
            ▼ opencode 106 s → review Claude → ACCETTATO
```

Perché due fasi e non una? Perché il comando (T3) **dipende** dalla logica (T2).
Se l'operaio le facesse insieme e sbagliasse la logica, dovresti rifare tutto.
Così invece la logica viene controllata e "congelata" prima di costruirci sopra.

### Cosa ha trovato Claude nelle review

| Fase | Test dell'operaio | Problema trovato da Claude | Come si è risolto |
|---|---|---|---|
| T1 (prova precedente) | 31 ✅ | 4 bug: crash con importo `NaN`, `1e2` e `1_000` accettati, data `2026-1-5` accettata, numero di riga sbagliato | Un giro di correzioni all'operaio + 1 ritocco di Claude |
| T2 | 63 ✅ | Se `check()` riceve un generatore, restituisce tutti zeri **senza dare errore** | 1 riga corretta da Claude + test |
| T3 | 78 ✅ | Spazi inutili a fine riga nella tabella | Ritocco di Claude |

Morale: **i test verdi dell'operaio non bastano**. La review di Claude serve proprio
a trovare quello che l'operaio non ha pensato di testare.

### Il risultato

```bash
$ python -m expenses budget examples/expenses.csv --budgets examples/budgets.csv
month    category    limit  spent  remaining  status
2026-01  food        25.00  37.44     -12.44  OVER
2026-01  transport   15.00  10.00       5.00  ok
...
$ python -m expenses budget examples/expenses.csv --budgets examples/budgets.csv --fail-on-over
... (exit code 1 perché c'è almeno un OVER)
```

### Quanto è costato

| | Tempo | Token operaio | Costo operaio |
|---|---|---|---|
| T1 + correzione | 151 s | ~52k in/out (+1M dalla cache) | $0 |
| T2 | 68 s | ~38k (+430k dalla cache) | $0 |
| T3 | 106 s | ~40k (+380k dalla cache) | $0 |

Tutto il codice e i 78 test li ha scritti l'operaio gratis; Claude ha speso i suoi
token solo per spec, brief e review.
