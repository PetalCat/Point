<script lang="ts">
	import { onMount } from 'svelte';

	let canvas: HTMLCanvasElement;
	let animFrame: number;

	interface Dot {
		x: number;
		y: number;
		vx: number;
		vy: number;
		color: string;
		radius: number;
		trail: { x: number; y: number; age: number }[];
		pulsePhase: number;
	}

	interface Geofence {
		x: number;
		y: number;
		radius: number;
		color: string;
		pulsePhase: number;
	}

	const COLORS = ['#3F51FF', '#FF3B8B', '#FF6B35', '#00D4FF', '#00FF88', '#B44DFF', '#FFD600'];

	onMount(() => {
		const ctx = canvas.getContext('2d')!;
		let w: number, h: number;
		let dots: Dot[] = [];
		let geofences: Geofence[] = [];
		let gridLines: { x1: number; y1: number; x2: number; y2: number }[] = [];

		function resize() {
			const dpr = window.devicePixelRatio || 1;
			const rect = canvas.getBoundingClientRect();
			w = rect.width;
			h = rect.height;
			canvas.width = w * dpr;
			canvas.height = h * dpr;
			ctx.scale(dpr, dpr);
			initElements();
		}

		function initElements() {
			// Create moving dots (people)
			dots = [];
			const dotCount = Math.min(12, Math.floor(w / 80));
			for (let i = 0; i < dotCount; i++) {
				dots.push({
					x: Math.random() * w,
					y: Math.random() * h,
					vx: (Math.random() - 0.5) * 0.6,
					vy: (Math.random() - 0.5) * 0.6,
					color: COLORS[i % COLORS.length],
					radius: 3 + Math.random() * 2,
					trail: [],
					pulsePhase: Math.random() * Math.PI * 2
				});
			}

			// Create geofences
			geofences = [];
			const geoCount = Math.min(4, Math.floor(w / 250));
			for (let i = 0; i < geoCount; i++) {
				geofences.push({
					x: w * 0.15 + Math.random() * w * 0.7,
					y: h * 0.15 + Math.random() * h * 0.7,
					radius: 40 + Math.random() * 60,
					color: COLORS[(i + 2) % COLORS.length],
					pulsePhase: Math.random() * Math.PI * 2
				});
			}

			// Create grid lines (map-like)
			gridLines = [];
			const spacing = 80;
			for (let x = 0; x < w; x += spacing) {
				gridLines.push({ x1: x, y1: 0, x2: x, y2: h });
			}
			for (let y = 0; y < h; y += spacing) {
				gridLines.push({ x1: 0, y1: y, x2: w, y2: y });
			}
		}

		function drawGrid(time: number) {
			ctx.strokeStyle = 'rgba(63, 81, 255, 0.04)';
			ctx.lineWidth = 1;
			for (const line of gridLines) {
				ctx.beginPath();
				ctx.moveTo(line.x1, line.y1);
				ctx.lineTo(line.x2, line.y2);
				ctx.stroke();
			}

			// Animated scan line
			const scanY = (time * 0.02) % (h + 100) - 50;
			const scanGrad = ctx.createLinearGradient(0, scanY - 30, 0, scanY + 30);
			scanGrad.addColorStop(0, 'transparent');
			scanGrad.addColorStop(0.5, 'rgba(63, 81, 255, 0.06)');
			scanGrad.addColorStop(1, 'transparent');
			ctx.fillStyle = scanGrad;
			ctx.fillRect(0, scanY - 30, w, 60);
		}

		function drawGeofences(time: number) {
			for (const gf of geofences) {
				const pulse = Math.sin(time * 0.002 + gf.pulsePhase) * 0.5 + 0.5;
				const r = gf.radius + pulse * 8;

				// Fill
				const grad = ctx.createRadialGradient(gf.x, gf.y, 0, gf.x, gf.y, r);
				grad.addColorStop(0, hexToRgba(gf.color, 0.05 + pulse * 0.03));
				grad.addColorStop(0.7, hexToRgba(gf.color, 0.02));
				grad.addColorStop(1, 'transparent');
				ctx.fillStyle = grad;
				ctx.beginPath();
				ctx.arc(gf.x, gf.y, r, 0, Math.PI * 2);
				ctx.fill();

				// Border
				ctx.strokeStyle = hexToRgba(gf.color, 0.15 + pulse * 0.1);
				ctx.lineWidth = 1;
				ctx.setLineDash([4, 4]);
				ctx.beginPath();
				ctx.arc(gf.x, gf.y, r, 0, Math.PI * 2);
				ctx.stroke();
				ctx.setLineDash([]);
			}
		}

		function drawDots(time: number) {
			for (const dot of dots) {
				// Update position
				dot.x += dot.vx;
				dot.y += dot.vy;

				// Bounce off edges softly
				if (dot.x < 0 || dot.x > w) dot.vx *= -1;
				if (dot.y < 0 || dot.y > h) dot.vy *= -1;

				// Slight random direction changes
				if (Math.random() < 0.01) {
					dot.vx += (Math.random() - 0.5) * 0.3;
					dot.vy += (Math.random() - 0.5) * 0.3;
					const speed = Math.sqrt(dot.vx * dot.vx + dot.vy * dot.vy);
					if (speed > 1) {
						dot.vx = (dot.vx / speed) * 0.8;
						dot.vy = (dot.vy / speed) * 0.8;
					}
				}

				// Add to trail
				dot.trail.push({ x: dot.x, y: dot.y, age: 0 });
				if (dot.trail.length > 60) dot.trail.shift();

				// Draw trail
				if (dot.trail.length > 2) {
					for (let i = 1; i < dot.trail.length; i++) {
						const t = dot.trail[i];
						const alpha = (i / dot.trail.length) * 0.3;
						ctx.strokeStyle = hexToRgba(dot.color, alpha);
						ctx.lineWidth = 1.5 * (i / dot.trail.length);
						ctx.beginPath();
						ctx.moveTo(dot.trail[i - 1].x, dot.trail[i - 1].y);
						ctx.lineTo(t.x, t.y);
						ctx.stroke();
					}
				}

				// Pulse ring
				const pulse = Math.sin(time * 0.003 + dot.pulsePhase) * 0.5 + 0.5;
				const ringRadius = dot.radius + 8 + pulse * 12;
				ctx.strokeStyle = hexToRgba(dot.color, 0.1 * (1 - pulse));
				ctx.lineWidth = 1;
				ctx.beginPath();
				ctx.arc(dot.x, dot.y, ringRadius, 0, Math.PI * 2);
				ctx.stroke();

				// Glow
				const glowGrad = ctx.createRadialGradient(dot.x, dot.y, 0, dot.x, dot.y, dot.radius * 4);
				glowGrad.addColorStop(0, hexToRgba(dot.color, 0.3));
				glowGrad.addColorStop(1, 'transparent');
				ctx.fillStyle = glowGrad;
				ctx.beginPath();
				ctx.arc(dot.x, dot.y, dot.radius * 4, 0, Math.PI * 2);
				ctx.fill();

				// Core dot
				ctx.fillStyle = dot.color;
				ctx.beginPath();
				ctx.arc(dot.x, dot.y, dot.radius, 0, Math.PI * 2);
				ctx.fill();

				// White center
				ctx.fillStyle = 'rgba(255,255,255,0.8)';
				ctx.beginPath();
				ctx.arc(dot.x, dot.y, dot.radius * 0.4, 0, Math.PI * 2);
				ctx.fill();
			}
		}

		function drawConnections() {
			for (let i = 0; i < dots.length; i++) {
				for (let j = i + 1; j < dots.length; j++) {
					const dx = dots[i].x - dots[j].x;
					const dy = dots[i].y - dots[j].y;
					const dist = Math.sqrt(dx * dx + dy * dy);
					if (dist < 150) {
						const alpha = (1 - dist / 150) * 0.08;
						ctx.strokeStyle = `rgba(63, 81, 255, ${alpha})`;
						ctx.lineWidth = 1;
						ctx.beginPath();
						ctx.moveTo(dots[i].x, dots[i].y);
						ctx.lineTo(dots[j].x, dots[j].y);
						ctx.stroke();
					}
				}
			}
		}

		function hexToRgba(hex: string, alpha: number): string {
			const r = parseInt(hex.slice(1, 3), 16);
			const g = parseInt(hex.slice(3, 5), 16);
			const b = parseInt(hex.slice(5, 7), 16);
			return `rgba(${r},${g},${b},${alpha})`;
		}

		function animate(time: number) {
			ctx.clearRect(0, 0, w, h);
			drawGrid(time);
			drawGeofences(time);
			drawConnections();
			drawDots(time);
			animFrame = requestAnimationFrame(animate);
		}

		resize();
		animFrame = requestAnimationFrame(animate);
		window.addEventListener('resize', resize);

		return () => {
			cancelAnimationFrame(animFrame);
			window.removeEventListener('resize', resize);
		};
	});
</script>

<div class="hero-map-container">
	<canvas bind:this={canvas} class="hero-canvas"></canvas>
	<div class="hero-vignette"></div>
</div>

<style>
	.hero-map-container {
		position: absolute;
		inset: 0;
		overflow: hidden;
	}

	.hero-canvas {
		width: 100%;
		height: 100%;
		display: block;
	}

	.hero-vignette {
		position: absolute;
		inset: 0;
		background: radial-gradient(ellipse 80% 60% at 50% 40%, transparent 30%, rgba(0,0,0,0.7) 70%, #000 100%);
		pointer-events: none;
	}
</style>
