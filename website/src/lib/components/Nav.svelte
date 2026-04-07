<script lang="ts">
	import { page } from '$app/state';

	let scrolled = $state(false);
	let mobileOpen = $state(false);

	const links = [
		{ href: '/', label: 'Home' },
		{ href: '/features', label: 'Features' },
		{ href: '/privacy', label: 'Privacy' },
		{ href: '/download', label: 'Download' },
		{ href: '/self-host', label: 'Self-Host' },
		{ href: '/about', label: 'About' }
	];

	function handleScroll() {
		scrolled = window.scrollY > 20;
	}

	function closeMobile() {
		mobileOpen = false;
	}
</script>

<svelte:window onscroll={handleScroll} />

<nav class="nav" class:scrolled>
	<div class="nav-inner">
		<a href="/" class="logo" onclick={closeMobile}>
			<img src="/point-icon.png" alt="Point" width="28" height="28" class="logo-icon" />
			<span class="logo-text">Point</span>
		</a>

		<div class="nav-links" class:open={mobileOpen}>
			{#each links as link}
				<a
					href={link.href}
					class="nav-link"
					class:active={page.url.pathname === link.href}
					onclick={closeMobile}
				>
					{link.label}
				</a>
			{/each}
			<a href="https://app.petalcat.dev" class="btn-primary nav-cta" target="_blank" rel="noopener">
				Get the App
			</a>
		</div>

		<button
			class="mobile-toggle"
			onclick={() => mobileOpen = !mobileOpen}
			aria-label={mobileOpen ? 'Close menu' : 'Open menu'}
			aria-expanded={mobileOpen}
		>
			<span class="bar" class:open={mobileOpen}></span>
			<span class="bar" class:open={mobileOpen}></span>
			<span class="bar" class:open={mobileOpen}></span>
		</button>
	</div>
</nav>

<style>
	.nav {
		position: fixed;
		top: 0;
		left: 0;
		right: 0;
		z-index: 100;
		padding: 1rem 0;
		transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1);
	}

	.nav.scrolled {
		background: rgba(0, 0, 0, 0.8);
		backdrop-filter: blur(20px);
		-webkit-backdrop-filter: blur(20px);
		border-bottom: 1px solid rgba(63, 81, 255, 0.1);
		padding: 0.6rem 0;
	}

	.nav-inner {
		max-width: 1200px;
		margin: 0 auto;
		padding: 0 1.5rem;
		display: flex;
		align-items: center;
		justify-content: space-between;
	}

	.logo {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		text-decoration: none;
		color: #fff;
	}

	.logo-icon {
		border-radius: 7px;
		z-index: 101;
	}

	.logo-text {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.3rem;
		letter-spacing: -0.03em;
	}

	.nav-links {
		display: flex;
		align-items: center;
		gap: 0.25rem;
	}

	.nav-link {
		font-family: var(--font-display);
		font-weight: 500;
		font-size: 0.9rem;
		color: var(--color-text-muted);
		text-decoration: none;
		padding: 0.5rem 0.85rem;
		border-radius: 8px;
		transition: all 0.2s ease;
	}

	.nav-link:hover {
		color: #fff;
		background: rgba(255, 255, 255, 0.05);
	}

	.nav-link.active {
		color: #fff;
		background: rgba(63, 81, 255, 0.15);
	}

	.nav-cta {
		margin-left: 0.75rem;
		padding: 0.6rem 1.4rem;
		font-size: 0.85rem;
	}

	.mobile-toggle {
		display: none;
		flex-direction: column;
		gap: 5px;
		background: none;
		border: none;
		cursor: pointer;
		padding: 4px;
		z-index: 101;
	}

	.bar {
		display: block;
		width: 22px;
		height: 2px;
		background: #fff;
		border-radius: 2px;
		transition: all 0.3s ease;
	}

	.bar.open:nth-child(1) {
		transform: translateY(7px) rotate(45deg);
	}

	.bar.open:nth-child(2) {
		opacity: 0;
	}

	.bar.open:nth-child(3) {
		transform: translateY(-7px) rotate(-45deg);
	}

	@media (max-width: 768px) {
		.mobile-toggle {
			display: flex;
		}

		.nav-links {
			position: fixed;
			inset: 0;
			background: rgba(0, 0, 0, 0.95);
			backdrop-filter: blur(20px);
			-webkit-backdrop-filter: blur(20px);
			flex-direction: column;
			justify-content: center;
			gap: 0.5rem;
			opacity: 0;
			pointer-events: none;
			transition: opacity 0.3s ease;
		}

		.nav-links.open {
			opacity: 1;
			pointer-events: all;
		}

		.nav-link {
			font-size: 1.3rem;
			padding: 0.75rem 1.5rem;
		}

		.nav-cta {
			margin-left: 0;
			margin-top: 1rem;
		}
	}
</style>
