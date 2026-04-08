<script lang="ts">
	import '../app.css';
	import Nav from '$lib/components/Nav.svelte';
	import Footer from '$lib/components/Footer.svelte';

	let { children } = $props();
</script>

<a href="#main-content" class="skip-link">Skip to content</a>
<Nav />
<main id="main-content">
	{@render children()}
</main>
<Footer />

<style>
	.skip-link {
		position: absolute;
		top: -100px;
		left: 0;
		background: var(--color-primary);
		color: #fff;
		padding: 0.5rem 1rem;
		z-index: 1000;
		font-weight: 700;
		font-size: 0.9rem;
		transition: top 0.2s;
	}
	.skip-link:focus {
		top: 0;
	}
</style>
