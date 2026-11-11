<script lang="ts">
	let {
		src,
		alt,
		width,
		radius = 38,
		bezel = 8,
		screenRadius = 30,
		shadow = 'var(--shadow-phone)'
	}: {
		src: string;
		alt: string;
		width: string;
		radius?: number;
		bezel?: number;
		screenRadius?: number;
		shadow?: string;
	} = $props();
</script>

<div class="frame" style:width style:border-radius="{radius}px" style:padding="{bezel}px" style:box-shadow={shadow}>
	<img {src} {alt} style:border-radius="{screenRadius}px" />
</div>

<style>
	.frame {
		max-width: 100%;
		background: var(--ink);
		box-sizing: border-box;
	}

	img {
		display: block;
		width: 100%;
		height: auto;
		aspect-ratio: 9 / 19.5;
		background: var(--paper);
	}
</style>
