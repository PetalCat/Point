<script lang="ts">
	import { reveal } from '$lib/actions/reveal';
</script>

<svelte:head>
	<title>About — Point</title>
	<meta name="description" content="The vision behind Point. Why we're building privacy-first location sharing." />
</svelte:head>

<section class="page-hero">
	<div class="container">
		<h1 use:reveal>
			Why <span class="gradient-text">Point</span> exists.
		</h1>
		<p class="page-hero-sub" use:reveal={{ delay: 100 }}>
			Location sharing shouldn't require trusting a corporation with your most sensitive data.
		</p>
	</div>
</section>

<section class="section">
	<div class="container">
		<!-- Vision -->
		<div class="vision" use:reveal>
			<div class="vision-content">
				<h2 class="section-label">The Problem</h2>
				<h3 class="section-title">Location sharing is <span class="gradient-text-warm">broken.</span></h3>
				<div class="prose">
					<p>
						Your partner uses Google Maps sharing. Your mom insists on Life360. Your keys
						have an AirTag. Your backpack has a Tile. Your family uses Find My. That's
						five apps to see where the people and things you care about are.
					</p>
					<p>
						Worse, each of these services has full access to your raw GPS data. Life360
						has been caught selling precise location data to brokers. Google uses it for
						ad targeting. Every one of them is a surveillance liability.
					</p>
					<p>
						Beeper solved this for messaging — one app, all platforms, bridged together.
						Point does the same for location. One beautiful map, every service bridged in,
						with end-to-end encryption so nobody except the people you choose can see where you are.
					</p>
				</div>
			</div>
		</div>

		<!-- Principles -->
		<div class="principles" use:reveal>
			<h2 class="section-label">Principles</h2>
			<h3 class="section-title">What we believe</h3>
			<div class="principles-list">
				{#each [
					{
						title: 'Privacy is a right, not a premium feature',
						desc: 'Encryption and data sovereignty are defaults, not upsells. Everyone deserves privacy regardless of what they pay.'
					},
					{
						title: 'Bridges, not lock-in',
						desc: 'We bridge existing services rather than demanding everyone switch. Meet people where they are.'
					},
					{
						title: 'Open source or it doesn\'t count',
						desc: 'Security claims without source code are marketing. Every line is public, auditable, and forkable on GitHub.'
					},
					{
						title: 'Self-hosting should be trivial',
						desc: 'One Docker command. No Kubernetes degree required. If it\'s hard to self-host, people won\'t.'
					},
					{
						title: 'Anti-surveillance is a design constraint',
						desc: 'Every feature is evaluated through the lens of "could this enable stalking?" If yes, we redesign it.'
					},
					{
						title: 'Federation over centralization (planned)',
						desc: 'No single server should be a single point of failure or control. Federation is planned so instances can connect and users can choose.'
					}
				] as principle, i}
					<div class="principle-row" use:reveal={{ delay: i * 60 }}>
						<div class="principle-idx">{String(i + 1).padStart(2, '0')}</div>
						<div>
							<h4>{principle.title}</h4>
							<p>{principle.desc}</p>
						</div>
					</div>
				{/each}
			</div>
		</div>

		<!-- Built By -->
		<div class="built-by" use:reveal>
			<h2 class="section-label">Built By</h2>
			<h3 class="section-title">Petalcat</h3>
			<p class="prose-single">
				Point is built by Petalcat — an independent developer focused on building
				privacy-respecting tools. No VC funding, no growth-at-all-costs pressure,
				no incentive to monetize your data. Just good software built for people who
				care about where their data goes.
			</p>
			<div class="about-links">
				<a href="#" class="btn-secondary">
					<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"/></svg>
					GitHub
				</a>
				<a href="https://app.petalcat.dev" class="btn-primary" target="_blank" rel="noopener">
					Try Point
				</a>
			</div>
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
		max-width: 560px;
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
		font-size: clamp(2rem, 5vw, 3rem);
		font-weight: 800;
		color: #fff;
		margin-bottom: 1.5rem;
	}

	/* Vision */
	.vision {
		margin-bottom: 5rem;
	}

	.prose {
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
		max-width: 700px;
	}

	.prose p {
		color: var(--color-text-muted);
		font-size: 1.05rem;
		line-height: 1.8;
	}

	.prose-single {
		color: var(--color-text-muted);
		font-size: 1.05rem;
		line-height: 1.8;
		max-width: 700px;
		margin-bottom: 2rem;
	}

	/* Principles */
	.principles {
		margin-bottom: 5rem;
	}

	.principles-list {
		display: flex;
		flex-direction: column;
		gap: 0;
	}

	.principle-row {
		display: flex;
		gap: 1.5rem;
		padding: 1.5rem 0;
		border-bottom: 1px solid var(--color-border);
		align-items: flex-start;
	}

	.principle-row:first-child {
		border-top: 1px solid var(--color-border);
	}

	.principle-idx {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.2rem;
		color: var(--color-primary);
		flex-shrink: 0;
		width: 40px;
		padding-top: 0.1rem;
	}

	.principle-row h4 {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1.1rem;
		color: #fff;
		margin-bottom: 0.35rem;
	}

	.principle-row p {
		color: var(--color-text-muted);
		font-size: 0.95rem;
		line-height: 1.6;
	}

	/* Built By */
	.built-by {
		margin-bottom: 3rem;
	}

	.about-links {
		display: flex;
		gap: 1rem;
		flex-wrap: wrap;
	}
</style>
