<script lang="ts">
	import { reveal } from '$lib/actions/reveal';
	import HeroMap from '$lib/components/HeroMap.svelte';
</script>

<svelte:head>
	<title>Point — Privacy-First Location Sharing</title>
	<meta name="description" content="Beeper for location. Unify all your location sharing — Find My, Google Maps, Life360, and more — into one encrypted, self-hostable app." />
	<meta property="og:title" content="Point — Privacy-First Location Sharing" />
	<meta property="og:description" content="Unify all your location sharing into one encrypted, self-hostable app." />
	<meta property="og:type" content="website" />
</svelte:head>

<!-- Hero -->
<section class="hero">
	<HeroMap />
	<div class="hero-content">
		<img src="/point-icon.png" alt="Point" class="hero-app-icon" use:reveal={{ delay: 0 }} width="80" height="80" />
		<div class="hero-badge" use:reveal={{ delay: 50 }}>
			<span class="badge-dot"></span>
			Open Source & Self-Hostable
		</div>
		<h1 use:reveal={{ delay: 100 }}>
			All your people.<br/>
			<span class="gradient-text">One map.</span>
		</h1>
		<p class="hero-sub" use:reveal={{ delay: 200 }}>
			See everyone in one place. Bridge Find My, Google Maps, Life360, and more
			into a single encrypted app you control. End-to-end encrypted. Self-hostable. Open source.
		</p>
		<div class="hero-actions" use:reveal={{ delay: 300 }}>
			<a href="https://app.petalcat.dev" class="btn-primary" target="_blank" rel="noopener">
				<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
				Get the App
			</a>
			<a href="https://github.com/PetalCat/Point" class="btn-secondary" target="_blank" rel="noopener">
				<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"/></svg>
				View on GitHub
			</a>
		</div>
	</div>
</section>

<!-- Bridges -->
<section class="section bridges" use:reveal>
	<div class="container">
		<h2 class="section-label">Bridges</h2>
		<h3 class="section-title">One app. <span class="gradient-text">Every platform.</span></h3>
		<p class="section-desc">Stop juggling apps. Point bridges all your location services into a single unified view.</p>
		<div class="bridge-grid">
			{#each [
				{ name: 'Find My', icon: '/bridges/findmy.svg', color: '#32D74B' },
				{ name: 'Google Maps', icon: '/bridges/googlemaps.svg', color: '#1A73E8' },
				{ name: 'Life360 / Tile', icon: '/bridges/life360.svg', color: '#7C3AED' },
				{ name: 'OwnTracks', icon: '/bridges/owntracks.svg', color: '#478DB2' },
				{ name: 'SmartTag', icon: '/bridges/smarttag.svg', color: '#FF3B8B' }
			] as bridge, i}
				<div class="bridge-card" use:reveal={{ delay: i * 80 }}>
					<div class="bridge-icon" style="--glow: {bridge.color}">
						<img src={bridge.icon} alt={bridge.name} height="40" />
					</div>
					<span class="bridge-name">{bridge.name}</span>
					<div class="bridge-status">
						<span class="status-dot" style="background: {bridge.color}"></span>
						Coming Soon
					</div>
				</div>
			{/each}
		</div>
	</div>
</section>

<!-- Features Highlight -->
<section class="section features-hl">
	<div class="container">
		<h2 class="section-label">Features</h2>
		<h3 class="section-title">Everything you need. <span class="gradient-text-warm">Nothing you don't.</span></h3>

		<div class="features-grid">
			{#each [
				{ title: 'Real-time Location', desc: 'See everyone on a live map with smooth position updates. Battery level and speed included.', icon: '⚡', color: '#FFD600' },
				{ title: 'E2E Encrypted', desc: 'Your location is encrypted on your device and only readable by the people you choose. The server never sees your data — not even the admin.', icon: '🔒', color: '#00FF88' },
				{ title: 'Geofencing', desc: 'Circle and polygon geofences with instant push notifications when people arrive or leave.', icon: '📐', color: '#3F51FF' },
				{ title: 'Ghost Mode', desc: 'Go invisible instantly. Pause all sharing with one tap. No one knows you went dark.', icon: '👻', color: '#B44DFF' },
				{ title: 'Trail History', desc: 'Heatmap history shows where people have been. Beautiful visualizations of movement patterns.', icon: '🗺️', color: '#FF6B35' },
				{ title: 'Groups & 1:1', desc: 'Share with groups, individuals, or create temporary shares that auto-expire.', icon: '👥', color: '#FF3B8B' },
				{ title: 'Self-Hostable', desc: 'Run your own server with Docker. Federation planned for connecting separate instances.', icon: '🐳', color: '#00D4FF' },
				{ title: 'Anti-Surveillance', desc: 'Bridged people can\'t be shared. Built-in protections against location tracking abuse.', icon: '🛡️', color: '#FF3B8B' }
			] as feature, i}
				<div class="feature-card" use:reveal={{ delay: i * 60 }} style="--accent: {feature.color}">
					<div class="feature-icon">{feature.icon}</div>
					<h4>{feature.title}</h4>
					<p>{feature.desc}</p>
					<div class="feature-glow"></div>
				</div>
			{/each}
		</div>
	</div>
</section>

<!-- Privacy CTA -->
<section class="section privacy-cta" use:reveal>
	<div class="container">
		<div class="privacy-card">
			<div class="privacy-card-bg"></div>
			<div class="privacy-content">
				<h2 class="section-label" style="color: #00FF88">Privacy-First</h2>
				<h3 class="section-title" style="max-width: 600px">Your location is <span class="gradient-text">yours</span>.</h3>
				<p class="section-desc" style="max-width: 500px">
					Point is built on zero-trust principles. Native sharing uses end-to-end encryption
					so not even the server can see where you are. Bridges encrypt at the edge on your
					hardware — the server stays zero-knowledge. Self-host for complete control.
				</p>
				<a href="/privacy" class="btn-primary" style="margin-top: 1.5rem;">
					Learn About Our Privacy
					<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>
				</a>
			</div>
			<div class="privacy-visual">
				<div class="lock-ring ring-1"></div>
				<div class="lock-ring ring-2"></div>
				<div class="lock-ring ring-3"></div>
				<div class="lock-icon">🔐</div>
			</div>
		</div>
	</div>
</section>

<!-- Self-Host CTA -->
<section class="section" use:reveal>
	<div class="container">
		<div class="terminal-card">
			<div class="terminal-header">
				<div class="terminal-dots">
					<span style="background: #FF5F57"></span>
					<span style="background: #FFBD2E"></span>
					<span style="background: #27C93F"></span>
				</div>
				<span class="terminal-title">Terminal</span>
			</div>
			<div class="terminal-body">
				<code>
					<span class="t-prompt">$</span> <span class="t-cmd">docker run</span> <span class="t-flag">-d</span> \{'\n'}
					&nbsp;&nbsp;<span class="t-flag">--name</span> point-server \{'\n'}
					&nbsp;&nbsp;<span class="t-flag">-p</span> <span class="t-val">8080:8080</span> \{'\n'}
					&nbsp;&nbsp;<span class="t-flag">-v</span> <span class="t-val">point-data:/data</span> \{'\n'}
					&nbsp;&nbsp;ghcr.io/petalcat/point-server:latest{'\n'}
					{'\n'}
					<span class="t-comment"># That's it. Your server is running. 🎉</span>
				</code>
			</div>
		</div>
		<div style="text-align: center; margin-top: 2rem;">
			<a href="/self-host" class="btn-secondary">
				Self-Hosting Guide
				<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>
			</a>
		</div>
	</div>
</section>

<!-- Final CTA -->
<section class="section final-cta" use:reveal>
	<div class="container" style="text-align: center;">
		<h3 class="section-title">Ready to take back<br/><span class="gradient-text">your location?</span></h3>
		<p class="section-desc">Join the movement for privacy-first location sharing.</p>
		<div class="hero-actions" style="justify-content: center; margin-top: 2rem;">
			<a href="https://app.petalcat.dev" class="btn-primary" target="_blank" rel="noopener">
				Download Point
			</a>
			<a href="https://github.com/PetalCat/Point" class="btn-secondary" target="_blank" rel="noopener">
				Star on GitHub
			</a>
		</div>
	</div>
</section>

<style>
	/* ---- Hero ---- */
	.hero {
		position: relative;
		min-height: 100vh;
		display: flex;
		align-items: center;
		justify-content: center;
		overflow: hidden;
	}

	.hero-content {
		position: relative;
		z-index: 10;
		text-align: center;
		padding: 0 1.5rem;
		max-width: 800px;
	}

	.hero-app-icon {
		border-radius: 20px;
		box-shadow: 0 4px 24px rgba(63, 81, 255, 0.4), 0 0 60px rgba(63, 81, 255, 0.15);
		margin-bottom: 1.5rem;
	}

	.hero-badge {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.4rem 1rem 0.4rem 0.75rem;
		background: rgba(63, 81, 255, 0.1);
		border: 1px solid rgba(63, 81, 255, 0.2);
		border-radius: 100px;
		font-family: var(--font-display);
		font-size: 0.8rem;
		font-weight: 500;
		color: var(--color-primary-light);
		margin-bottom: 1.5rem;
	}

	.badge-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: var(--color-green);
		animation: pulse-dot 2s ease-in-out infinite;
	}

	.hero h1 {
		font-size: clamp(2.8rem, 8vw, 5.5rem);
		font-weight: 900;
		color: #fff;
		margin-bottom: 1.25rem;
		line-height: 1.05;
	}

	.hero-sub {
		font-size: clamp(1rem, 2.5vw, 1.2rem);
		color: var(--color-text-muted);
		line-height: 1.7;
		max-width: 560px;
		margin: 0 auto 2rem;
	}

	.hero-actions {
		display: flex;
		gap: 1rem;
		flex-wrap: wrap;
		justify-content: center;
	}

	/* ---- Sections ---- */
	.section {
		padding: 6rem 0;
	}

	.container {
		max-width: 1200px;
		margin: 0 auto;
		padding: 0 1.5rem;
	}

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
		font-size: clamp(2rem, 5vw, 3.2rem);
		font-weight: 800;
		color: #fff;
		margin-bottom: 1rem;
		line-height: 1.1;
	}

	.section-desc {
		font-size: 1.1rem;
		color: var(--color-text-muted);
		line-height: 1.7;
		max-width: 600px;
	}

	/* ---- Bridges ---- */
	.bridges {
		text-align: center;
	}

	.bridges .section-desc {
		margin: 0 auto 3rem;
	}

	.bridge-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
		gap: 1rem;
		max-width: 900px;
		margin: 0 auto;
	}

	.bridge-card {
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 16px;
		padding: 1.5rem 1rem;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.75rem;
		transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
	}

	.bridge-card:hover {
		border-color: rgba(63, 81, 255, 0.15);
	}

	.bridge-icon {
		width: 56px;
		height: 56px;
		display: flex;
		align-items: center;
		justify-content: center;
		border-radius: 14px;
		overflow: hidden;
		filter: drop-shadow(0 0 12px var(--glow));
	}

	.bridge-icon img {
		width: 100%;
		height: 100%;
		border-radius: 14px;
	}

	.bridge-name {
		font-family: var(--font-display);
		font-weight: 600;
		font-size: 0.95rem;
		color: #fff;
	}

	.bridge-status {
		display: flex;
		align-items: center;
		gap: 0.35rem;
		font-size: 0.75rem;
		color: var(--color-text-muted);
	}

	.status-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
	}

	/* ---- Feature Cards ---- */
	.features-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
		gap: 1.25rem;
		margin-top: 3rem;
	}

	.feature-card {
		position: relative;
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 16px;
		padding: 1.75rem;
		overflow: hidden;
		transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
	}

	.feature-card:hover {
		border-color: var(--accent);
		transform: translateY(-3px);
	}

	.feature-card:hover .feature-glow {
		opacity: 1;
	}

	.feature-icon {
		font-size: 1.5rem;
		margin-bottom: 1rem;
	}

	.feature-card h4 {
		font-family: var(--font-display);
		font-size: 1.1rem;
		font-weight: 700;
		color: #fff;
		margin-bottom: 0.5rem;
	}

	.feature-card p {
		font-size: 0.9rem;
		color: var(--color-text-muted);
		line-height: 1.6;
	}

	.feature-glow {
		position: absolute;
		top: -50%;
		left: -50%;
		width: 200%;
		height: 200%;
		background: radial-gradient(circle at 30% 30%, var(--accent), transparent 60%);
		opacity: 0;
		transition: opacity 0.4s ease;
		pointer-events: none;
		mix-blend-mode: overlay;
		filter: blur(40px);
	}

	/* ---- Privacy CTA ---- */
	.privacy-card {
		position: relative;
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 24px;
		padding: 4rem;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 3rem;
		overflow: hidden;
	}

	.privacy-card-bg {
		position: absolute;
		inset: 0;
		background: radial-gradient(ellipse at 80% 50%, rgba(63, 81, 255, 0.06) 0%, transparent 60%);
		pointer-events: none;
	}

	.privacy-content {
		position: relative;
		z-index: 1;
	}

	.privacy-visual {
		position: relative;
		width: 200px;
		height: 200px;
		flex-shrink: 0;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.lock-ring {
		position: absolute;
		border-radius: 50%;
		border: 1px solid rgba(63, 81, 255, 0.15);
	}

	.lock-ring.ring-1 {
		width: 100%;
		height: 100%;
		animation: geofence-pulse 4s ease-in-out infinite;
	}

	.lock-ring.ring-2 {
		width: 70%;
		height: 70%;
		border-color: rgba(0, 255, 136, 0.15);
		animation: geofence-pulse 4s ease-in-out infinite 1s;
	}

	.lock-ring.ring-3 {
		width: 40%;
		height: 40%;
		border-color: rgba(180, 77, 255, 0.2);
		animation: geofence-pulse 4s ease-in-out infinite 2s;
	}

	.lock-icon {
		font-size: 2.5rem;
		position: relative;
		z-index: 1;
	}

	/* ---- Terminal ---- */
	.terminal-card {
		max-width: 650px;
		margin: 0 auto;
		background: #0A0A12;
		border: 1px solid var(--color-border);
		border-radius: 12px;
		overflow: hidden;
	}

	.terminal-header {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 0.75rem 1rem;
		background: rgba(255, 255, 255, 0.02);
		border-bottom: 1px solid var(--color-border);
	}

	.terminal-dots {
		display: flex;
		gap: 6px;
	}

	.terminal-dots span {
		width: 10px;
		height: 10px;
		border-radius: 50%;
	}

	.terminal-title {
		font-family: var(--font-display);
		font-size: 0.75rem;
		color: var(--color-text-muted);
	}

	.terminal-body {
		padding: 1.5rem;
		font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
		font-size: 0.85rem;
		line-height: 1.8;
		overflow-x: auto;
	}

	.terminal-body code {
		white-space: pre;
	}

	.t-prompt { color: var(--color-green); }
	.t-cmd { color: #fff; }
	.t-flag { color: var(--color-cyan); }
	.t-val { color: var(--color-yellow); }
	.t-comment { color: var(--color-text-muted); }

	/* ---- Final CTA ---- */
	.final-cta {
		padding-bottom: 2rem;
	}

	.final-cta .section-desc {
		margin: 0 auto;
	}

	/* ---- Responsive ---- */
	@media (max-width: 768px) {
		.section {
			padding: 4rem 0;
		}

		.privacy-card {
			flex-direction: column;
			padding: 2.5rem 1.5rem;
			text-align: center;
		}

		.privacy-visual {
			width: 150px;
			height: 150px;
		}

		.privacy-content {
			display: flex;
			flex-direction: column;
			align-items: center;
		}

		.bridge-grid {
			grid-template-columns: repeat(2, 1fr);
		}
	}
</style>
