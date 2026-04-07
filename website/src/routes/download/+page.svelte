<script lang="ts">
	import { reveal } from '$lib/actions/reveal';
</script>

<svelte:head>
	<title>Download — Point</title>
	<meta name="description" content="Download Point for Android. iOS and F-Droid coming soon." />
</svelte:head>

<section class="page-hero">
	<div class="container">
		<h1 use:reveal>
			Get <span class="gradient-text">Point.</span>
		</h1>
		<p class="page-hero-sub" use:reveal={{ delay: 100 }}>
			Available now for Android. More platforms coming soon.
		</p>
	</div>
</section>

<section class="section">
	<div class="container">
		<div class="download-grid">
			<!-- Android -->
			<div class="download-card available" use:reveal={{ delay: 0 }}>
				<div class="dl-icon">
					<svg width="48" height="48" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
						<path d="M17.523 2.239a.75.75 0 0 0-1.046.206l-1.232 1.827A7.265 7.265 0 0 0 12 3.5c-1.16 0-2.26.265-3.245.772L7.523 2.445a.75.75 0 1 0-1.252.84l1.14 1.69A7.478 7.478 0 0 0 4.5 11h15a7.478 7.478 0 0 0-2.91-6.025l1.14-1.69a.75.75 0 0 0-.207-1.046zM9.5 8.5a1 1 0 1 1-2 0 1 1 0 0 1 2 0zM16.5 8.5a1 1 0 1 1-2 0 1 1 0 0 1 2 0z" fill="#00FF88"/>
						<path d="M4.5 12.5v5A2.5 2.5 0 0 0 7 20h10a2.5 2.5 0 0 0 2.5-2.5v-5h-15z" fill="#00FF88" opacity="0.5"/>
						<rect x="2" y="12" width="2" height="6" rx="1" fill="#00FF88" opacity="0.7"/>
						<rect x="20" y="12" width="2" height="6" rx="1" fill="#00FF88" opacity="0.7"/>
					</svg>
				</div>
				<h3>Android</h3>
				<p>Download the APK directly. No Play Store required.</p>
				<span class="dl-status available-badge">Available Now</span>
				<a href="https://app.petalcat.dev" class="btn-primary" target="_blank" rel="noopener" style="width: 100%; justify-content: center;">
					Download APK
				</a>
			</div>

			<!-- iOS -->
			<div class="download-card coming-soon" use:reveal={{ delay: 100 }}>
				<div class="dl-icon" style="opacity: 0.4;">
					<svg width="48" height="48" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
						<path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83z" fill="#fff"/>
						<path d="M15.25 2c.06 1.52-.58 2.98-1.52 3.97-.93 1-2.47 1.77-3.98 1.67-.08-1.46.64-2.98 1.52-3.94C12.2 2.72 13.82 2.05 15.25 2z" fill="#fff" opacity="0.8"/>
					</svg>
				</div>
				<h3>iOS</h3>
				<p>iPhone and iPad support is in development.</p>
				<span class="dl-status soon-badge">Coming Soon</span>
				<button class="btn-secondary" disabled style="width: 100%; justify-content: center; opacity: 0.5; cursor: not-allowed;">
					Coming Soon
				</button>
			</div>

			<!-- F-Droid -->
			<div class="download-card coming-soon" use:reveal={{ delay: 200 }}>
				<div class="dl-icon" style="opacity: 0.4;">
					<svg width="48" height="48" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
						<rect x="5" y="2" width="14" height="20" rx="3" stroke="#00D4FF" stroke-width="1.5" fill="none"/>
						<circle cx="12" cy="12" r="4" stroke="#00D4FF" stroke-width="1.5" fill="none"/>
						<circle cx="12" cy="12" r="1.5" fill="#00D4FF"/>
					</svg>
				</div>
				<h3>F-Droid</h3>
				<p>Fully open source build planned for F-Droid.</p>
				<span class="dl-status soon-badge">Coming Soon</span>
				<button class="btn-secondary" disabled style="width: 100%; justify-content: center; opacity: 0.5; cursor: not-allowed;">
					Coming Soon
				</button>
			</div>
		</div>

		<!-- Requirements -->
		<div class="requirements" use:reveal>
			<h3>System Requirements</h3>
			<div class="req-grid">
				<div class="req-item">
					<h4>Android</h4>
					<p>Android 8.0 (Oreo) or later</p>
				</div>
				<div class="req-item">
					<h4>Permissions</h4>
					<p>Location (foreground & background), Notifications</p>
				</div>
				<div class="req-item">
					<h4>Server</h4>
					<p>Use the public instance or self-host your own</p>
				</div>
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
		max-width: 500px;
		margin: 0 auto;
		line-height: 1.7;
	}

	.section { padding: 3rem 0; }
	.container { max-width: 1200px; margin: 0 auto; padding: 0 1.5rem; }

	.download-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
		gap: 1.5rem;
		margin-bottom: 4rem;
	}

	.download-card {
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 20px;
		padding: 2.5rem 2rem;
		text-align: center;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 1rem;
		transition: all 0.3s ease;
	}

	.download-card.available {
		border-color: rgba(0, 255, 136, 0.2);
	}

	.download-card.available:hover {
		border-color: rgba(0, 255, 136, 0.4);
		transform: translateY(-4px);
		box-shadow: 0 12px 40px rgba(0, 255, 136, 0.1);
	}

	.dl-icon {
		margin-bottom: 0.5rem;
	}

	.download-card h3 {
		font-family: var(--font-display);
		font-size: 1.4rem;
		font-weight: 800;
		color: #fff;
	}

	.download-card p {
		color: var(--color-text-muted);
		font-size: 0.9rem;
		line-height: 1.6;
	}

	.dl-status {
		font-family: var(--font-display);
		font-size: 0.75rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		padding: 0.3rem 0.75rem;
		border-radius: 100px;
	}

	.available-badge {
		background: rgba(0, 255, 136, 0.1);
		color: var(--color-green);
		border: 1px solid rgba(0, 255, 136, 0.2);
	}

	.soon-badge {
		background: rgba(255, 255, 255, 0.03);
		color: var(--color-text-muted);
		border: 1px solid var(--color-border);
	}

	/* Requirements */
	.requirements {
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 20px;
		padding: 2.5rem;
	}

	.requirements h3 {
		font-family: var(--font-display);
		font-size: 1.3rem;
		font-weight: 700;
		color: #fff;
		margin-bottom: 1.5rem;
	}

	.req-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
		gap: 1.5rem;
	}

	.req-item h4 {
		font-family: var(--font-display);
		font-weight: 600;
		color: var(--color-primary-light);
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		margin-bottom: 0.35rem;
	}

	.req-item p {
		color: var(--color-text-muted);
		font-size: 0.9rem;
		line-height: 1.5;
	}
</style>
