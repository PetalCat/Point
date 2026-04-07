# OwnTracks Message Formats

The OwnTracks mobile apps publish location data in JSON over MQTT.  There are several `_type` values with well‑defined schemas.  For example, a **location** update has `_type:"location"` and **required** `lat`, `lon`, and `tst` (timestamp) fields, plus optional metadata like accuracy (`acc`), altitude (`alt`), bearing (`cog`), battery (`batt`), and trigger type (`t`)【10†L102-L105】【10†L118-L119】.  A **waypoint** (`_type:"waypoint"`) includes `lat`, `lon`, a radius `rad`, a description `desc`, and a timestamp `tst`【9†L273-L279】【9†L280-L281】.  A **transition** message (`_type:"transition"`) reports entering or leaving a region or beacon, with fields like `event` (`"enter"`/`"leave"`), time (`t` and `tst`), latitude/longitude, `acc`, and optional `desc` for region name【9†L318-L324】【9†L328-L334】.  (There are other types too, e.g. **waypoints** for bulk lists, **lwt** for last-will info, **status** and **cmd** for device diagnostics, **encrypted** payloads, etc.)  In MQTT mode, devices publish to topics of the form `owntracks/<user>/<device>` or `owntracks/<user>/<device>/<event>`. 

- **Location** (`_type:"location"`): Required `lat`, `lon`, `tst` (GPS fix time).  Optional fields include `acc` (accuracy in meters), `alt` (altitude), `batt` (battery %), `cog` (bearing), `vel` (speed), and a trigger `t` that flags how the report was generated (e.g. `"p"` for periodic ping)【10†L102-L105】【10†L118-L119】.  
- **Transition** (`_type:"transition"`): Reports region events. Contains `event` (e.g. `"enter"`/`"leave"`), `t`, `tst`, `lat`, `lon`, plus optional `acc`, `desc` (region name), and `tid` (tracker ID)【9†L318-L324】【9†L328-L334】.  
- **Waypoint** (`_type:"waypoint"`): A point of interest. Includes `lat`, `lon`, `rad` (radius), `desc` (label), and `tst` (time)【9†L273-L279】.  
- **Waypoints** (`_type:"waypoints"`): A collection of waypoints. This message is an array of waypoint objects under the key `waypoints`【11†L642-L645】.  
- **Other types**: e.g. `encrypted` (payload in `data` field), `status` (device info), `cmd` (remote command), `card` (user card), `lwt` (last will), etc.  These have their own JSON schemas (see the OwnTracks JSON docs).  

Each message payload is valid JSON and typically contains `_type` to identify its schema.  For example, a sample location report might look like `{"_type":"location","lat":48.86,"lon":2.29,"tst":1610000000,"acc":12,"batt":88,"t":"u"}`.  Consumers can validate against the schema defined in the OwnTracks documentation【10†L102-L105】【9†L273-L279】.  (In practice, our bridge would parse these fields and map them into our own internal location data model.)

## MQTT Bridge Design

A typical bridge service subscribes to the OwnTracks MQTT topics (e.g. `owntracks/+/+/#`) and transforms messages into the server’s internal format.  In practice, you would run an MQTT client (in Rust, Python, etc.) that connects to the broker, listens on `owntracks/<user>/<device>`, parses the incoming JSON, and inserts or republishes data as needed.  For example, one approach is to take each parsed location and insert it into your Postgres database with user/device metadata.  Alternatively (as in *realtime sharing* apps) you might republish it on new topics or push updates to WebSockets.  Key steps include decrypting if necessary (OwnTracks can encrypt payloads), validating the JSON schema, and mapping fields (`lat`,`lon`,`tst`, etc.) to your tables or objects.

Many projects show similar patterns.  For instance, the [Pinpoint](https://github.com/jhotmann/pinpoint) OwnTracks server reads each `_type:location` message and **republishes it to every friend’s topic** under the user’s configuration【59†L91-L99】.  Pinpoint even “takes the hassle out of configuring the OwnTracks app” by auto-generating a special configuration link for each device【59†L91-L99】.  Concretely, its design is:
- Subscribe to `owntracks/<user>/<device>`.
- Look up that user’s friends/groups in its database.
- For each friend, republish the payload to `owntracks/<friend>/<device>`.
- Generate a unique “OwnTracks Link” (`owntracks://...`) for onboarding the device in the mobile app【59†L91-L99】.

While Pinpoint is Node-based, the same logic applies in any language.  In Rust, you might use the [rumqttc](https://crates.io/crates/rumqttc) or [async-mqtt](https://crates.io/crates/mqtt-async-client) crates to subscribe, then use `serde_json` to deserialize, and finally execute database INSERTs or new MQTT publishes.  The exact “internal format” is up to your server design, but the bridge essentially acts as a translator between the standard OwnTracks JSON fields and your system’s schema.

## Single-Binary Deployment Models

Many modern self-hosted servers aim to be delivered as a single (or few) executables with minimal dependencies.  For example, Conduit (a Rust Matrix homeserver) is distributed as a *statically-linked single binary* (often targeting musl) so that no shared libraries are needed【17†L33-L40】.  Its Docker/Debian releases bundle everything, and it can use an embedded storage engine (RocksDB or SQLite) to avoid requiring an external database【17†L137-L141】.  Likewise, Gitea (a Go Git server) is distributed as a single static binary (with embedded assets) that supports SQLite, MySQL or Postgres via compile-time flags【18†L71-L74】.  The Gitea binary includes all templates and resources internally, so you just run one executable (or Docker container) and point it at a DB or use SQLite for a zero-dependency mode【18†L71-L74】.

Plausible Analytics (an open‑source web analytics) is a heavier example: it is a Phoenix/Elixir app but is also typically run via Docker.  It is **not** a single monolith — it requires PostgreSQL for metadata and ClickHouse for event stats【20†L189-L193】.  In its case, “single-binary” doesn’t apply; instead the deployment is multiple services (two DBs plus the Plausible app).  However, Plausible still simplifies upgrades by providing a self-hosted Docker image and scripts.  The key takeaway is that even single-binary projects often need at least a database or messaging component.  Conduit and Gitea minimize external deps by bundling DB engines (or using SQLite), while systems like Plausible rely on external databases and use Docker Compose to tie them together. 

## Docker Compose Stack Patterns

A robust self-hosted stack typically uses Docker Compose (or Kubernetes) to run all components: the location server, a database, an MQTT broker, and any other services.  For example, the [owntrack-rs](https://github.com/pka/owntrack-rs) project provides a sample `docker-compose.yml` that sets up the Rust server, a Caddy reverse proxy (for TLS), and a SQLite database【25†L345-L354】.  The essential pattern is:

- **Server**: Your Rust (or other) service. Run it as a container, exposing HTTP (and/or MQTT/WebSockets) ports. Pass configuration via environment variables (e.g. `DB_CONNECTION=sqlite://...` for SQLite or a Postgres URI)【25†L413-L419】【25†L426-L427】.
- **Database**: Typically PostgreSQL (for scalability) or SQLite (for minimalism). In Compose, add a Postgres service. Owntrack-rs shows setting `DB_CONNECTION=postgres://user:pass@postgres:5432/dbname` to use Postgres【25†L426-L427】.
- **MQTT Broker**: e.g. [Eclipse Mosquitto](https://mosquitto.org/) or [VerneMQ](https://vernemq.com/). Run a Mosquitto container with persisted config. OwnTrack apps will publish to it. (For testing you can also use a local network, but typically we Dockerize it.)
- **Bridges/Helpers**: If needed, add a “bridge” container (e.g. a small Python/Rust service) to transform messages, or a visualization front-end. In many cases you write the bridge logic into the main server, so no extra container is needed.
- **Reverse Proxy**: Optionally a proxy like Traefik or Caddy (see below) in front of the HTTP server.

A Compose setup might look roughly like this:

```yaml
version: "3.8"
services:
  db:
    image: postgres:15
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: owntracks
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypass

  mqtt:
    image: eclipse-mosquitto
    volumes:
      - mosquitto_data:/mosquitto/data

  server:
    image: mydomain/owntracks-server:latest
    depends_on:
      - db
      - mqtt
    environment:
      - DB_CONNECTION=postgres://myuser:mypass@db:5432/owntracks
      - MQTT_URL=tcp://mqtt:1883
      - MQTT_USER=user  # if secured
      - MQTT_PASSWORD=secret
      - HTTP_LISTEN=0.0.0.0:8080

  # Optional: Caddy for HTTPS (see TLS section below)
  caddy:
    image: caddy
    volumes:
      - caddy_data:/data
      - caddy_config:/config
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - server

volumes:
  pgdata:
  mosquitto_data:
  caddy_data:
  caddy_config:
```

In this example, the Rust service uses `DB_CONNECTION` and `MQTT_URL` from environment (as owntrack-rs does【25†L426-L427】【25†L401-L404】). The Mosquitto container is the MQTT broker. The Caddy service fronts it for TLS. This pattern can be extended with additional services (Redis for caching, a separate frontend UI, etc.). The key is that Docker Compose ties the full stack (server + Postgres + MQTT + proxy) in a single YAML for easy deployment.

## Automatic TLS (ACME) vs Reverse Proxy

For HTTPS, you can use a built-in ACME solution or front your server with a proxy that handles certificates.  **Caddy** is a popular choice because it has native Let’s Encrypt support: in a Compose network it can automatically obtain/renew TLS certs for your domain and reverse-proxy to your server.  For example, Pinpoint’s docs explicitly *recommend* “host[ing] Pinpoint behind a reverse proxy that handles SSL/TLS, my personal favorite is Caddy”【59†L30-L33】.  You’d label or configure Caddy with your domain, and it will route traffic to the server container with HTTPS out-of-the-box.

Alternatively, you can use **Nginx/Apache** as a reverse proxy with Certbot.  In this setup, the proxy container obtains certs (via Docker volume + Certbot or an image like [linuxserver/letsencrypt](https://hub.docker.com/r/linuxserver/letsencrypt)) and forwards `443` to your app.  This is more manual: you must configure hostnames and renewal yourself. 

A third approach is an **embedded library** in your Rust app (e.g. [rustls](https://github.com/ctz/rustls) + [acme](https://github.com/rustls/acme-client)), but this is uncommon.  Most self-hosted services simply assume you’ll use a proxy.  Either way, an automated TLS solution is highly recommended so that end users can securely connect without manual cert handling.  If you do use a proxy, ensure WebSockets or MQTT-over-WSS are properly forwarded. The bottom line: **Caddy/Traefik** give one-command HTTPS, whereas with Nginx/Apache you handle LetsEncrypt yourself. (Pinpoint’s example and many Docker Compose guides use Caddy as the simplest path【59†L30-L33】.)

## User Onboarding and Account Creation

Without a central authority, self-hosted apps typically make the first registered user the administrator, and then allow either open sign-ups or invite-only registration under admin control.  For example:

- **Conduit (Matrix homeserver)**: Automatically grants admin privileges to the first user that registers【49†L246-L251】.  In fact, Conduit’s docs say “Conduit automatically makes the first user an admin. To create the account, simply register using a Matrix client”【49†L246-L251】.  After that, admins can disable public registration if desired.
- **Gitea (Git service)**: Has no built-in admin password. The first user to sign up (via the web UI) is given admin privileges【43†L839-L842】.  (This is confirmed by Gitea templates: “The first user registered … will have administration privileges”【43†L839-L842】.)  The admin user can then invite or create additional users via the admin panel.
- **Plausible (self-hosted analytics)**: Does *not* provide a web signup at all.  New user accounts (including the initial admin) must be created using a CLI/console command.  For example, you run `docker exec plausible /app/bin/plausible remote` and then call `Auth.User.new(...) |> Repo.insert` to add a user【51†L249-L254】.  In practice, the installer creates an initial admin via environment variables or a migration script, and any others must be added manually or via an admin API.
- **Invite-only flows**: Some systems use invitation links or codes.  For instance, the Pinpoint OwnTracks server lists **“Generate registration links”** as a feature【30†L303-L307】.  In such a model, the admin can create a one-time link and send it to a friend; using that link lets the friend set up an account with pre-approved access.  (Your app could do something similar: issue invite codes that new users must provide to register.)  

【58†embed_image】 In the example above, the Pinpoint server’s web UI is shown. Pinpoint offers a built-in interface where an admin/user can add a new device (“Add Device”), invite friends (“Add Friend”), and see current devices and sharing groups【30†L303-L307】【59†L96-L99】.  The right panel lists “Devices” and “Friends,” showing that user “tester” will receive updates from device “pixel3a.”  Notice how Pinpoint even creates an “OwnTracks Link” (a special URI) that the mobile app can import automatically【59†L96-L99】.  This illustrates one possible onboarding UX: after initial signup, the user adds their device and configures sharing through a web page, without needing any centralized service.

## Update Mechanisms for Self-Hosts

Keeping a self-hosted server up-to-date usually relies on publishing version releases and having clear upgrade steps.  Most projects use GitHub releases or Docker tags:

- **Release notifications**: Encourage users to **watch the GitHub repo or RSS feed** for new releases.  You might also announce updates via a community forum or email list.  (There isn’t a universal standard; some admins manually subscribe to feeds or use tools like [changedetection.io](https://github.com/dgtlmoon/changedetection.io) on the releases page.)
- **Pulling new images**: If you run Docker Compose, a simple update step is `docker-compose pull` followed by `docker-compose up -d`.  Gitea’s documentation explicitly says: “`docker pull` the latest Gitea release, stop the instance, backup data, then start the new container”【54†L132-L140】.  Similarly, Conduit and others provide new binaries that you `wget` or copy in place.  After replacing the binary, the app usually performs any DB migrations on startup.
- **Backup/Upgrade scripts**: As a convenience, Gitea even offers a community-maintained `upgrade.sh` script to automate download/replace/backup steps【54†L151-L158】.  You could provide a similar script or just document the steps clearly.  Plausible’s self-hosted docs include detailed instructions (backing up Postgres and ClickHouse volumes, then pulling new versions).
- **In-app updates**: Few self-hosted apps auto-update themselves (for security reasons).  Some systems (like Bitwarden RS, Home Assistant) have built-in “update available” banners or one-click UI updates.  If desired, you could add a version check endpoint (hit GitHub API) and notify admins in your web UI when a newer release is detected.
- **Automation tools**: Tools like [Watchtower](https://github.com/containrrr/watchtower) can monitor Docker image registries and restart containers on new image pushes.  This makes “painless” updates possible (at the cost of auto-restarts and needing container labeling).

In summary, the typical pattern is: **announce a new release**, **provide upgrade instructions**, and let admins either manually pull and restart or use helper scripts.  As best practice, include a migration strategy (e.g. database migration on startup) and clear “backup your data” warnings.  For example, Gitea’s docs say to always backup config and DB before upgrading【54†L132-L140】.  In our service’s release notes, we should similarly note any breaking changes and outline step-by-step upgrade (matching what Gitea does in its documentation【54†L132-L140】【54†L151-L158】).

**Sources:** Official OwnTracks JSON docs【10†L102-L105】【9†L273-L279】; OwnTracks Recorder/Bridge guides【25†L345-L354】【25†L401-L404】; Conduit and Gitea deployment guides【17†L33-L40】【18†L71-L74】; Pinpoint and Plausible project docs【59†L91-L99】【51†L249-L254】; Gitea upgrade docs【54†L132-L140】【54†L151-L158】, etc.