<script lang="ts">
	import { reveal } from '$lib/actions/reveal';
</script>

<svelte:head>
	<title>Privacy — Point</title>
	<meta name="description" content="Point is built on zero-trust, zero-knowledge principles. End-to-end encryption, anti-surveillance protections, and full self-hosting." />
</svelte:head>

<section class="page-hero">
	<div class="container">
		<h1 use:reveal>
			Privacy isn't a feature.<br/>
			<span class="gradient-text">It's the architecture.</span>
		</h1>
		<p class="page-hero-sub" use:reveal={{ delay: 100 }}>
			Location data is the most sensitive data you have. Point treats it that way.
		</p>
	</div>
</section>

<section class="section">
	<div class="container">
		<!-- Principles -->
		<div class="principles-grid">
			{#each [
				{
					title: 'Zero-Knowledge Server',
					desc: 'The Point server never sees your location. It relays encrypted blobs between devices. Even if the server is seized or compromised, your location history is unreadable gibberish.',
					icon: '🧊',
					color: '#3F51FF'
				},
				{
					title: 'End-to-End Encryption',
					desc: 'Three tiers of privacy: Native sharing is fully E2E encrypted using MLS — only your device and recipients can read it. Self-hosted bridges encrypt before sending to the server, which only sees ciphertext. Cloud-hosted bridges process plaintext from the source platform before encrypting — for maximum privacy, self-host your bridges on hardware you control.',
					icon: '🔐',
					color: '#00FF88'
				},
				{
					title: 'Anti-Surveillance by Design',
					desc: 'Bridged contacts can never be re-shared. Ghost mode is silent. There are no "who viewed your location" features. We actively prevent the patterns that enable stalking and surveillance.',
					icon: '🛡️',
					color: '#FF3B8B'
				},
				{
					title: 'Self-Hostable',
					desc: 'Run your own server. Your data never touches infrastructure you don\'t control. Docker makes deployment trivial. Federation (planned) will let you connect with other instances.',
					icon: '🏠',
					color: '#00D4FF'
				},
				{
					title: 'Open Source',
					desc: 'The client, the server, the bridges, the protocol — all on GitHub. Security through transparency, not obscurity. Audit it yourself.',
					icon: '📖',
					color: '#B44DFF'
				},
				{
					title: 'No Tracking. No Ads. No Selling.',
					desc: 'Point has no analytics, no trackers, no advertising, no data sales. The business model is "people pay for software" not "people are the product."',
					icon: '🚫',
					color: '#FFD600'
				}
			] as principle, i}
				<div class="principle-card" use:reveal={{ delay: i * 80 }} style="--accent: {principle.color}">
					<div class="principle-icon">{principle.icon}</div>
					<h3>{principle.title}</h3>
					<p>{principle.desc}</p>
				</div>
			{/each}
		</div>

		<!-- How It Works -->
		<div class="how-section" use:reveal>
			<h2 class="section-label">How It Works</h2>
			<h3 class="section-title">The encryption flow</h3>
			<div class="flow-steps">
				{#each [
					{ step: '01', title: 'Device encrypts with MLS', desc: 'Your phone encrypts GPS coordinates using MLS (RFC 9420) with X25519 key exchange and ChaCha20-Poly1305 authenticated encryption. Post-quantum upgrade path via XWing is planned.' },
					{ step: '02', title: 'Encrypted blob sent to server', desc: 'The encrypted blob is sent to the server. The server cannot read it — it is zero-knowledge. It stores and forwards only ciphertext.' },
					{ step: '03', title: 'Server relays to recipients', desc: 'The server relays the encrypted blob to recipient devices. It never decrypts anything.' },
					{ step: '04', title: 'Recipients decrypt on-device', desc: 'Only devices with the MLS group keys can decrypt and display the location. Historical data stays encrypted — database dumps are useless without device keys.' }
				] as step, i}
					<div class="flow-step" use:reveal={{ delay: i * 100 }}>
						<div class="step-num">{step.step}</div>
						<div class="step-content">
							<h4>{step.title}</h4>
							<p>{step.desc}</p>
						</div>
					</div>
				{/each}
			</div>
		</div>

		<!-- Comparison -->
		<div class="comparison" use:reveal>
			<h2 class="section-label">Comparison</h2>
			<h3 class="section-title">How Point compares</h3>
			<div class="table-wrap">
				<table>
					<thead>
						<tr>
							<th></th>
							<th class="highlight">Point</th>
							<th>Life360</th>
							<th>Find My</th>
							<th>Google Maps</th>
						</tr>
					</thead>
					<tbody>
						<tr>
							<td>E2E Encrypted</td>
							<td class="highlight yes">Yes</td>
							<td class="no">No</td>
							<td class="partial">Partial</td>
							<td class="no">No</td>
						</tr>
						<tr>
							<td>Self-Hostable</td>
							<td class="highlight yes">Yes</td>
							<td class="no">No</td>
							<td class="no">No</td>
							<td class="no">No</td>
						</tr>
						<tr>
							<td>Open Source</td>
							<td class="highlight yes">Yes</td>
							<td class="no">No</td>
							<td class="no">No</td>
							<td class="no">No</td>
						</tr>
						<tr>
							<td>Cross-Platform Bridges</td>
							<td class="highlight yes">Yes</td>
							<td class="no">No</td>
							<td class="no">No</td>
							<td class="no">No</td>
						</tr>
						<tr>
							<td>Ghost Mode (Silent)</td>
							<td class="highlight yes">Yes</td>
							<td class="bad">Alerts Others</td>
							<td class="partial">Limited</td>
							<td class="partial">Limited</td>
						</tr>
						<tr>
							<td>Anti-Surveillance</td>
							<td class="highlight yes">Built-in</td>
							<td class="no">No</td>
							<td class="no">No</td>
							<td class="no">No</td>
						</tr>
						<tr>
							<td>Sells Your Data</td>
							<td class="highlight yes">Never</td>
							<td class="bad">Yes</td>
							<td class="partial">Indirect</td>
							<td class="bad">Yes</td>
						</tr>
					</tbody>
				</table>
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
		max-width: 520px;
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

	/* Principles */
	.principles-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
		gap: 1.25rem;
		margin-bottom: 5rem;
	}

	.principle-card {
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 16px;
		padding: 2rem;
		transition: all 0.3s ease;
	}

	.principle-card:hover {
		border-color: var(--accent);
		transform: translateY(-2px);
	}

	.principle-icon {
		font-size: 2rem;
		margin-bottom: 1rem;
	}

	.principle-card h3 {
		font-family: var(--font-display);
		font-size: 1.15rem;
		font-weight: 700;
		color: #fff;
		margin-bottom: 0.75rem;
	}

	.principle-card p {
		color: var(--color-text-muted);
		font-size: 0.9rem;
		line-height: 1.7;
	}

	/* Flow */
	.how-section {
		margin-bottom: 5rem;
	}

	.flow-steps {
		display: flex;
		flex-direction: column;
		gap: 1.5rem;
	}

	.flow-step {
		display: flex;
		align-items: flex-start;
		gap: 1.5rem;
		padding: 1.5rem;
		background: var(--color-bg-card);
		border: 1px solid var(--color-border);
		border-radius: 16px;
	}

	.step-num {
		font-family: var(--font-display);
		font-weight: 900;
		font-size: 1.5rem;
		color: var(--color-primary);
		flex-shrink: 0;
		width: 50px;
	}

	.step-content h4 {
		font-family: var(--font-display);
		font-weight: 700;
		color: #fff;
		margin-bottom: 0.35rem;
	}

	.step-content p {
		color: var(--color-text-muted);
		font-size: 0.9rem;
		line-height: 1.6;
	}

	/* Table */
	.comparison {
		margin-bottom: 3rem;
	}

	.table-wrap {
		overflow-x: auto;
		border: 1px solid var(--color-border);
		border-radius: 16px;
		/* Scroll hint gradient on mobile */
		-webkit-mask-image: linear-gradient(to right, #000 85%, transparent 100%);
		mask-image: linear-gradient(to right, #000 85%, transparent 100%);
	}
	.table-wrap:hover, .table-wrap:focus-within {
		-webkit-mask-image: none;
		mask-image: none;
	}

	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.9rem;
	}

	th, td {
		padding: 1rem 1.25rem;
		text-align: left;
		border-bottom: 1px solid var(--color-border);
		white-space: nowrap;
	}

	th {
		font-family: var(--font-display);
		font-weight: 600;
		color: var(--color-text-muted);
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		background: var(--color-bg-card);
	}

	th.highlight {
		color: var(--color-primary-light);
	}

	td:first-child {
		color: var(--color-text);
		font-weight: 500;
	}

	.highlight {
		background: rgba(63, 81, 255, 0.05);
	}

	.yes { color: var(--color-green); font-weight: 600; }
	.no { color: #666; }
	.bad { color: #ef4444; font-weight: 600; }
	.partial { color: var(--color-yellow); }

	tbody tr:last-child td {
		border-bottom: none;
	}

	@media (max-width: 768px) {
		.principles-grid {
			grid-template-columns: 1fr;
		}
	}
</style>
