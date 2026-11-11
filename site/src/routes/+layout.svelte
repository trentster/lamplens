<script lang="ts">
	import '../app.css';
	import type { LayoutProps } from './$types';
	import Header from '#lib/Header.svelte';
	import Footer from '#lib/Footer.svelte';

	let { children }: LayoutProps = $props();
</script>

<Header />
{@render children()}
<Footer />
