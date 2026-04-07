<script lang="ts">
	import { reveal } from '$lib/actions/reveal';
</script>

<svelte:head>
	<title>Features — Point</title>
	<meta name="description" content="Real-time location sharing, encryption, geofencing, ghost mode, trails, and more. Everything you need in one privacy-first app." />
</svelte:head>

<section class="page-hero">
	<div class="container">
		<h1 use:reveal>
			Built for <span class="gradient-text">real life.</span>
		</h1>
		<p class="page-hero-sub" use:reveal={{ delay: 100 }}>
			Every feature designed with privacy at its core. No compromises.
		</p>
	</div>
</section>

<!-- Feature Deep Dives -->
<section class="section">
	<div class="container">
		{#each [
			{
				label: 'Core',
				title: 'Real-Time Location Sharing',
				desc: 'See your people on a beautiful live map. Smooth position updates, battery level indicators, speed readouts, and last-seen timestamps. Precision controls let each person choose exactly how accurately they share — down to the neighborhood, city, or exact GPS coordinates.',
				color: '#3F51FF',
				icon: '📍',
				details: ['Real-time position updates', 'Battery & speed indicators', 'Precision control (exact / neighborhood / city)', 'Dark mode optimized map']
			},
			{
				label: 'Security',
				title: 'End-to-End Encryption',
				desc: 'Native sharing is fully end-to-end encrypted using MLS (RFC 9420) with X25519 key exchange, ChaCha20-Poly1305 encryption, and Ed25519 signatures. The server is zero-knowledge. Bridges encrypt at the edge — your bridge runs on YOUR infrastructure, not ours, so the server never sees plaintext. Post-quantum upgrade path via XWing (X25519 + ML-KEM hybrid) is ready when the ecosystem aligns.',
				color: '#00FF88',
				icon: '🔐',
				details: ['Zero-knowledge server architecture', 'MLS protocol (RFC 9420) with X25519 + ChaCha20-Poly1305', 'Bridge encrypts on your hardware before reaching the server', 'Open source on GitHub']
			},
			{
				label: 'Boundaries',
				title: 'Geofencing',
				desc: 'Draw circles or complex polygons on the map to create geofences. Get instant push notifications when someone arrives at or leaves a zone. Perfect for knowing when your partner gets home, when kids arrive at school, or when your delivery driver is close.',
				color: '#FF6B35',
				icon: '📐',
				details: ['Circle & polygon geofences', 'Arrive & leave notifications', 'Per-person geofence alerts', 'No limit on active geofences']
			},
			{
				label: 'Control',
				title: 'Ghost Mode',
				desc: 'Go invisible with a single tap. Ghost mode pauses all location sharing instantly — and nobody is notified that you went dark. Your privacy is your business.',
				color: '#B44DFF',
				icon: '👻',
				details: ['One-tap activation', 'No notifications to others', 'Per-group ghost settings']
			},
			{
				label: 'History',
				title: 'Trails & Heatmaps',
				desc: 'Beautiful heatmap visualizations show movement history over time. See where your people have been with smooth trail animations. All history is end-to-end encrypted and stored on your server — never sold, never analyzed.',
				color: '#FF3B8B',
				icon: '🗺️',
				details: ['Animated trail playback', 'Heatmap visualization', 'Date range filtering', 'E2E encrypted history']
			},
			{
				label: 'Social',
				title: 'Groups & Sharing',
				desc: 'Create groups for family, friends, coworkers. Share 1:1 with anyone. Create temporary share links that auto-expire after a set time. Role management lets you control who can see what within each group.',
				color: '#00D4FF',
				icon: '👥',
				details: ['Unlimited groups', '1:1 direct sharing', 'Temporary share links', 'Role-based permissions']
			}
		] as feature, i}
			<div class="feature-deep" class:reverse={i % 2 === 1} use:reveal>
				<div class="feature-deep-content">
					<span class="feature-label" style="color: {feature.color}">{feature.label}</span>
					<h3>{feature.title}</h3>
					<p>{feature.desc}</p>
					<ul class="feature-details">
						{#each feature.details as detail}
							<li>
								<span class="detail-check" style="color: {feature.color}">&#10003;</span>
								{detail}
							</li>
						{/each}
					</ul>
				</div>
				<div class="feature-deep-visual">
					<div class="visual-card" style="--accent: {feature.color}">
						<div class="visual-icon">{feature.icon}</div>
						<div class="visual-rings">
							<div class="v-ring r1"></div>
							<div class="v-ring r2"></div>
						</div>
					</div>
				</div>
			</div>
		{/each}
	</div>
</section>

<!-- Bridges Section -->
<section class="section" style="text-align: center;" use:reveal>
	<div class="container">
		<h2 class="section-label">Bridges</h2>
		<h3 class="section-title">Bridge everything to one <span class="gradient-text">Point.</span></h3>
		<p class="section-desc" style="margin: 0 auto 3rem;">
			Point bridges into existing location platforms so you can see everyone in one place — without
			making them switch apps.
		</p>
		<div class="bridge-list">
			{#each [
				{ name: 'Apple Find My', desc: 'See AirTags, iPhones, Macs, and Find My-shared contacts', icon: '/bridges/findmy.svg' },
				{ name: 'Google Maps', desc: 'Bridge Google Maps location sharing into Point', icon: '/bridges/googlemaps.svg' },
				{ name: 'Life360 / Tile', desc: 'Import Life360 circles and Tile trackers without the surveillance baggage', icon: '/bridges/life360.svg' },
				{ name: 'SmartTag', desc: 'Samsung SmartTag and SmartTag2 device tracking', icon: '/bridges/smarttag.svg' },
				{ name: 'OwnTracks', desc: 'Compatible with the OwnTracks protocol for custom setups', icon: '/bridges/owntracks.svg' },
				{ name: 'More Coming', desc: 'Open bridge API for community-built integrations', icon: '/point-icon.png' }
			] as bridge, i}
				<div class="bridge-item" use:reveal={{ delay: i * 60 }}>
					<div class="bridge-item-header">
						<img src={bridge.icon} alt={bridge.name} class="bridge-item-icon" width="36" height="36" />
						<h4>{bridge.name} <span class="coming-soon-tag">Coming Soon</span></h4>
					</div>
					<p>{bridge.desc}</p>
				</div>
			{/each}
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
		font-size: clamp(2rem, 5vw, 3rem);
		font-weight: 800;
		color: #fff;
		margin-bottom: 1rem;
	}

	.section-desc {
		font-size: 1.05rem;
		color: var(--color-text-muted);
		line-height: 1.7;
		max-width: 600px;
	}

	/* Feature Deep Dive */
	.feature-deep {
		display: flex;
		align-items: center;
		gap: 4rem;
		padding: 4rem 0;
		border-bottom: 1px solid var(--color-border);
	}

	.feature-deep:last-child {
		border-bottom: none;
	}

	.feature-deep.reverse {
		flex-direction: row-reverse;
	}

	.feature-deep-content {
		flex: 1;
	}

	.feature-label {
		font-family: var(--font-display);
		font-size: 0.8rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.1em;
		display: block;
		margin-bottom: 0.75rem;
	}

	.feature-deep-content h3 {
		font-size: 2rem;
		font-weight: 800;
		color: #fff;
		margin-bottom: 1rem;
	}

	.feature-deep-content p {
		color: var(--color-text-muted);
		line-height: 1.7;
		margin-bottom: 1.5rem;
	}

	.feature-details {
		list-style: none;
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}

	.feature-details li {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		color: var(--color-text);
		font-size: 0.95rem;
	}

	.detail-check {
		font-weight: 700;
		font-size: 0.85rem;
	}

	/* Visual Card */
	.feature-deep-visual {
		flex: 0 0 280px;
	}

	.visual-card {
		position: relative;
		width: 280px;
		height: 280px;
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 24px;
		display: flex;
		align-items: center;
		justify-content: center;
		overflow: hidden;
	}

	.visual-icon {
		font-size: 4rem;
		position: relative;
		z-index: 2;
	}

	.visual-rings {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.v-ring {
		position: absolute;
		border-radius: 50%;
		border: 1px solid var(--accent);
		opacity: 0.15;
	}

	.v-ring.r1 {
		width: 180px;
		height: 180px;
		animation: geofence-pulse 4s ease-in-out infinite;
	}

	.v-ring.r2 {
		width: 240px;
		height: 240px;
		animation: geofence-pulse 4s ease-in-out infinite 1.5s;
	}

	/* Bridge List */
	.bridge-list {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
		gap: 1.25rem;
		text-align: left;
	}

	.bridge-item {
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 16px;
		padding: 1.5rem;
		transition: all 0.3s ease;
	}

	.bridge-item:hover {
		border-color: rgba(63, 81, 255, 0.3);
		transform: translateY(-2px);
	}

	.bridge-item-header {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		margin-bottom: 0.5rem;
	}

	.bridge-item-icon {
		border-radius: 10px;
		flex-shrink: 0;
	}

	.bridge-item h4 {
		font-family: var(--font-display);
		font-weight: 700;
		color: #fff;
		margin-bottom: 0;
	}

	.bridge-item p {
		font-size: 0.9rem;
		color: var(--color-text-muted);
		line-height: 1.6;
	}

	.coming-soon-tag {
		display: inline-block;
		font-size: 0.6rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		padding: 0.15rem 0.5rem;
		background: rgba(255, 255, 255, 0.05);
		border: 1px solid var(--color-border);
		border-radius: 100px;
		color: var(--color-text-muted);
		vertical-align: middle;
		margin-left: 0.4rem;
	}

	@media (max-width: 768px) {
		.feature-deep, .feature-deep.reverse {
			flex-direction: column;
			gap: 2rem;
		}

		.feature-deep-visual {
			flex: none;
			width: 100%;
			display: flex;
			justify-content: center;
		}

		.visual-card {
			width: 200px;
			height: 200px;
		}
	}
</style>
