<script lang="ts">
	import { reveal } from '$lib/actions/reveal';
</script>

<svelte:head>
	<title>Self-Host — Point</title>
	<meta name="description" content="Run your own Point server with Docker. Complete control over your location data." />
</svelte:head>

<section class="page-hero">
	<div class="container">
		<h1 use:reveal>
			Your server.<br/>
			<span class="gradient-text">Your rules.</span>
		</h1>
		<p class="page-hero-sub" use:reveal={{ delay: 100 }}>
			Deploy Point in minutes with Docker. Zero-knowledge by design.
		</p>
	</div>
</section>

<section class="section">
	<div class="container">
		<!-- Quick Start -->
		<div class="quickstart" use:reveal>
			<h2 class="section-label">Quick Start</h2>
			<h3 class="section-title">Up and running in 60 seconds</h3>

			<div class="steps">
				<div class="step" use:reveal={{ delay: 0 }}>
					<div class="step-header">
						<span class="step-num">1</span>
						<h4>Pull & Run</h4>
					</div>
					<div class="code-block">
						<div class="code-header">
							<span>Terminal</span>
							<button class="copy-btn" aria-label="Copy to clipboard">Copy</button>
						</div>
						<pre><code><span class="t-prompt">$</span> docker run -d \
  --name point-server \
  -p 8080:8080 \
  -v point-data:/data \
  ghcr.io/petalcat/point-server:latest</code></pre>
					</div>
				</div>

				<div class="step" use:reveal={{ delay: 100 }}>
					<div class="step-header">
						<span class="step-num">2</span>
						<h4>Configure (Optional)</h4>
					</div>
					<div class="code-block">
						<div class="code-header">
							<span>docker-compose.yml</span>
						</div>
						<pre><code><span class="t-key">version</span>: <span class="t-str">"3.8"</span>
<span class="t-key">services</span>:
  <span class="t-key">point</span>:
    <span class="t-key">image</span>: <span class="t-str">ghcr.io/petalcat/point-server:latest</span>
    <span class="t-key">ports</span>:
      - <span class="t-str">"8080:8080"</span>
    <span class="t-key">volumes</span>:
      - <span class="t-str">point-data:/data</span>
    <span class="t-key">environment</span>:
      - <span class="t-val">POINT_DOMAIN=point.example.com</span>
      - <span class="t-val">POINT_FEDERATION=true</span> <span class="t-comment"># planned</span>
    <span class="t-key">restart</span>: <span class="t-str">unless-stopped</span>

<span class="t-key">volumes</span>:
  <span class="t-key">point-data</span>:</code></pre>
					</div>
				</div>

				<div class="step" use:reveal={{ delay: 200 }}>
					<div class="step-header">
						<span class="step-num">3</span>
						<h4>Connect Your App</h4>
					</div>
					<p class="step-desc">
						Open Point on your phone, go to Settings, and enter your server URL.
						That's it. All your data now flows through your own infrastructure.
					</p>
				</div>
			</div>
		</div>

		<!-- Features -->
		<div class="host-features" use:reveal>
			<h2 class="section-label">Server Features</h2>
			<h3 class="section-title">What you get</h3>
			<div class="hf-grid">
				{#each [
					{ title: 'Zero-Knowledge', desc: 'The server never decrypts location data. It\'s encrypted at rest and in transit.', icon: '🧊' },
					{ title: 'Federation (planned)', desc: 'Connect your instance to others. Share across servers without centralizing data. Coming soon.', icon: '🌐' },
					{ title: 'Low Resources', desc: 'Runs on a Raspberry Pi. Minimal CPU, RAM, and storage requirements.', icon: '⚡' },
					{ title: 'Auto Updates', desc: 'Use Watchtower or similar to keep your server automatically updated.', icon: '🔄' },
					{ title: 'Backups', desc: 'Simple volume-based backups. Your data is a single SQLite file.', icon: '💾' },
					{ title: 'API Access', desc: 'Full REST API for building custom integrations and automations.', icon: '🔌' }
				] as feature, i}
					<div class="hf-card" use:reveal={{ delay: i * 60 }}>
						<span class="hf-icon">{feature.icon}</span>
						<h4>{feature.title}</h4>
						<p>{feature.desc}</p>
					</div>
				{/each}
			</div>
		</div>

		<!-- Reverse Proxy -->
		<div class="proxy-section" use:reveal>
			<h2 class="section-label">Production Setup</h2>
			<h3 class="section-title">Reverse proxy with Caddy</h3>
			<p class="section-desc" style="margin-bottom: 1.5rem;">
				For production, put Point behind a reverse proxy with automatic HTTPS.
			</p>
			<div class="code-block">
				<div class="code-header">
					<span>Caddyfile</span>
				</div>
				<pre><code><span class="t-key">point.example.com</span> {'{'}
  <span class="t-cmd">reverse_proxy</span> <span class="t-str">localhost:8080</span>
{'}'}</code></pre>
			</div>
			<p class="note">
				Caddy automatically provisions and renews TLS certificates. You can also use nginx, Traefik, or any other reverse proxy.
			</p>
		</div>
	</div>
</section>

<style>
	.page-hero {
		padding: 10rem 0 4rem;
		text-align: center;
	}

	.page-hero h1 {
		font-size: clamp(2.5rem, 7vw, 4.5rem);
		font-weight: 900;
		color: #fff;
		margin-bottom: 1rem;
	}

	.page-hero-sub {
		font-size: 1.15rem;
		color: var(--color-text-muted);
		max-width: 500px;
		margin: 0 auto;
		line-height: 1.7;
	}

	.section { padding: 3rem 0; }
	.container { max-width: 1200px; margin: 0 auto; padding: 0 1.5rem; }
	.section-label {
		font-family: var(--font-display);
		font-size: 0.8rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.12em;
		color: var(--color-primary-light);
		margin-bottom: 0.75rem;
	}
	.section-title {
		font-size: clamp(1.8rem, 4vw, 2.5rem);
		font-weight: 800;
		color: #fff;
		margin-bottom: 1.5rem;
	}
	.section-desc {
		font-size: 1rem;
		color: var(--color-text-muted);
		line-height: 1.7;
	}

	/* Steps */
	.quickstart { margin-bottom: 5rem; }

	.steps {
		display: flex;
		flex-direction: column;
		gap: 2rem;
	}

	.step {
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 16px;
		padding: 2rem;
	}

	.step-header {
		display: flex;
		align-items: center;
		gap: 1rem;
		margin-bottom: 1.25rem;
	}

	.step-num {
		width: 32px;
		height: 32px;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-primary);
		border-radius: 8px;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.9rem;
		color: #fff;
	}

	.step-header h4 {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1.1rem;
		color: #fff;
	}

	.step-desc {
		color: var(--color-text-muted);
		line-height: 1.7;
		font-size: 0.95rem;
	}

	/* Code Block */
	.code-block {
		background: #06060C;
		border: 1px solid var(--color-border);
		border-radius: 10px;
		overflow: hidden;
	}

	.code-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 0.6rem 1rem;
		background: rgba(255, 255, 255, 0.02);
		border-bottom: 1px solid var(--color-border);
		font-family: var(--font-display);
		font-size: 0.75rem;
		color: var(--color-text-muted);
	}

	.copy-btn {
		background: rgba(255, 255, 255, 0.05);
		border: 1px solid var(--color-border);
		border-radius: 6px;
		padding: 0.25rem 0.6rem;
		font-size: 0.7rem;
		color: var(--color-text-muted);
		cursor: pointer;
		font-family: var(--font-display);
		transition: all 0.2s ease;
	}

	.copy-btn:hover {
		background: rgba(63, 81, 255, 0.1);
		color: var(--color-primary-light);
		border-color: var(--color-primary);
	}

	pre {
		padding: 1.25rem;
		overflow-x: auto;
		font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
		font-size: 0.85rem;
		line-height: 1.7;
	}

	.t-prompt { color: var(--color-green); }
	.t-key { color: var(--color-cyan); }
	.t-str { color: var(--color-yellow); }
	.t-cmd { color: #fff; }
	.t-val { color: var(--color-orange); }

	/* Host Features */
	.host-features {
		margin-bottom: 5rem;
	}

	.hf-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
		gap: 1.25rem;
	}

	.hf-card {
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 14px;
		padding: 1.5rem;
		transition: all 0.3s ease;
	}

	.hf-card:hover {
		border-color: rgba(63, 81, 255, 0.3);
		transform: translateY(-2px);
	}

	.hf-icon {
		font-size: 1.5rem;
		display: block;
		margin-bottom: 0.75rem;
	}

	.hf-card h4 {
		font-family: var(--font-display);
		font-weight: 700;
		color: #fff;
		margin-bottom: 0.4rem;
	}

	.hf-card p {
		color: var(--color-text-muted);
		font-size: 0.85rem;
		line-height: 1.6;
	}

	/* Proxy */
	.proxy-section { margin-bottom: 3rem; }

	.note {
		margin-top: 1rem;
		font-size: 0.85rem;
		color: var(--color-text-muted);
		line-height: 1.6;
	}
</style>
