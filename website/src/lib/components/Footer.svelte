<footer class="footer">
	<div class="footer-glow"></div>
	<div class="footer-inner">
		<div class="footer-grid">
			<div class="footer-brand">
				<div class="footer-logo">
					<img src="/point-icon.png" alt="Point" width="24" height="24" style="border-radius: 6px;" />
					<span>Point</span>
				</div>
				<p class="footer-tagline">Privacy-first location sharing.<br/>Your data, your rules.</p>
			</div>

			<div class="footer-col">
				<h4>Product</h4>
				<a href="/features">Features</a>
				<a href="/download">Download</a>
				<a href="/self-host">Self-Host</a>
				<a href="/privacy">Privacy</a>
			</div>

			<div class="footer-col">
				<h4>Community</h4>
				<a href="https://github.com/PetalCat/Point" target="_blank" rel="noopener">GitHub</a>
				<a href="#" target="_blank" rel="noopener">Discord</a>
				<a href="#" target="_blank" rel="noopener">Matrix</a>
			</div>

			<div class="footer-col">
				<h4>Legal</h4>
				<a href="/privacy">Privacy Policy</a>
				<a href="/about">About</a>
			</div>
		</div>

		<div class="footer-bottom">
			<p>&copy; {new Date().getFullYear()} Point by Petalcat. <a href="https://github.com/PetalCat/Point" target="_blank" rel="noopener" style="color: inherit; text-decoration: underline;">Open source.</a></p>
		</div>
	</div>
</footer>

<style>
	.footer {
		position: relative;
		border-top: 1px solid var(--color-border);
		padding: 4rem 0 2rem;
		margin-top: 6rem;
		overflow: hidden;
	}

	.footer-glow {
		position: absolute;
		top: -100px;
		left: 50%;
		transform: translateX(-50%);
		width: 600px;
		height: 200px;
		background: radial-gradient(ellipse, rgba(63, 81, 255, 0.08) 0%, transparent 70%);
		pointer-events: none;
	}

	.footer-inner {
		max-width: 1200px;
		margin: 0 auto;
		padding: 0 1.5rem;
		position: relative;
	}

	.footer-grid {
		display: grid;
		grid-template-columns: 2fr 1fr 1fr 1fr;
		gap: 3rem;
	}

	.footer-logo {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.2rem;
		color: #fff;
		margin-bottom: 0.75rem;
	}

	.footer-tagline {
		color: var(--color-text-muted);
		font-size: 0.9rem;
		line-height: 1.6;
	}

	.footer-col {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}

	.footer-col h4 {
		font-family: var(--font-display);
		font-weight: 600;
		font-size: 0.85rem;
		color: #fff;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		margin-bottom: 0.5rem;
	}

	.footer-col a {
		color: var(--color-text-muted);
		text-decoration: none;
		font-size: 0.9rem;
		transition: color 0.2s ease;
	}

	.footer-col a:hover {
		color: var(--color-primary-light);
	}

	.footer-bottom {
		margin-top: 3rem;
		padding-top: 1.5rem;
		border-top: 1px solid var(--color-border);
		text-align: center;
	}

	.footer-bottom p {
		color: var(--color-text-muted);
		font-size: 0.8rem;
	}

	@media (max-width: 768px) {
		.footer-grid {
			grid-template-columns: 1fr 1fr;
			gap: 2rem;
		}

		.footer-brand {
			grid-column: 1 / -1;
		}
	}

	@media (max-width: 480px) {
		.footer-grid {
			grid-template-columns: 1fr;
		}
	}
</style>
