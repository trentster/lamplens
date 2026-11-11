<script lang="ts">
	import Logo from './Logo.svelte';
</script>

<header>
	<a class="brand" href="/">
		<Logo />
		<span>Lamplens</span>
	</a>
	<a class="get" href="/#download">Get the app</a>
</header>

<style>
	header {
		max-width: var(--container);
		margin: 0 auto;
		padding: 20px var(--gutter);
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 16px;
	}

	.brand {
		display: flex;
		align-items: center;
		gap: 12px;
		text-decoration: none;
		color: var(--ink);
	}

	.brand span {
		font-size: clamp(20px, 6vw, 24px);
		font-weight: 500;
		letter-spacing: -0.01em;
	}

	.get {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
		padding: 8px 18px;
		border-radius: 999px;
		background: var(--ink);
		color: #ffffff;
		text-decoration: none;
		font-size: 16px;
		font-weight: 500;
		white-space: nowrap;
	}

	.get:hover {
		color: #ffffff;
		transition: opacity 120ms ease;
		opacity: 0.88;
	}
</style>
