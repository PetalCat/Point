<script lang="ts">
	import { page } from '$app/state';
</script>

<svelte:head>
	<title>404 — Point</title>
</svelte:head>

<section class="error-page">
	<div class="error-content">
		<div class="error-code">{page.status}</div>
		<h1>Lost signal.</h1>
		<p>This page doesn't exist — but your location data is still safe.</p>
		<a href="/" class="btn-primary">Back to Home</a>
	</div>
</section>

<style>
	.error-page {
		min-height: 80vh;
		display: flex;
		align-items: center;
		justify-content: center;
		text-align: center;
		padding: 2rem;
	}

	.error-code {
		font-size: clamp(4rem, 15vw, 8rem);
		font-weight: 900;
		color: var(--color-primary);
		opacity: 0.15;
		line-height: 1;
		margin-bottom: -1rem;
	}

	h1 {
		font-size: clamp(1.5rem, 4vw, 2.5rem);
		font-weight: 800;
		color: #fff;
		margin-bottom: 0.5rem;
	}

	p {
		color: var(--color-text-muted);
		margin-bottom: 2rem;
		font-size: 1rem;
	}
</style>
