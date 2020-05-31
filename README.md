# TheGuardian
TheGuardian exposes mitigation techniques for cache-based side channel attacks by devising a secure LLC replacement policy. Tests were conducted on ChampSim to make it immune to such cross-core eviction attacks.

## Usage

The `run_mitigation_tests.sh` script builds and executes ChampSim sequentially with [inclusive caches](https://en.wikipedia.org/wiki/Cache_inclusion_policy) with the various (modified) LLC replacement policies under [`replacement/*.llc_repl`](https://github.com/layman-n-ish/TheGuardian/tree/master/replacement). The required results are extracted from the simulation runs and stored appropriately under [`benchmarks/`](https://github.com/layman-n-ish/TheGuardian/tree/master/benchmarks).

Before running the script, set:
```
LEVEL (cmdline): 'b' for build, 'r' for run, 'a' for both build and run,
N_CORES: number of cores to run ChampSim simulation on,
N_WARMUP_INSTR: number of warmup instructions,
N_SIM_INSTR: number of simulation instructions,
N_LLC_SETS: number of sets in LLC,
N_LLC_WAYS: number of ways in LLC
TRACE_n: n-th trace file to run ChampSim on (depends on N_CORES)
```

Finally, 

```
$ ./run_mitigation_tests.sh a
> 
Building ChampSim with drrip as the LLC replacement policy...
Building ChampSim with lru as the LLC replacement policy...
Building ChampSim with lru_sharp as the LLC replacement policy...
Building ChampSim with lru_sharp_max as the LLC replacement policy...
Building ChampSim with ship as the LLC replacement policy...
Building ChampSim with srrip as the LLC replacement policy...

Running bimodal-no-no-no-no-drrip-2core binary...
Running bimodal-no-no-no-no-lru-2core binary...
Running bimodal-no-no-no-no-lru_sharp-2core binary...
Running bimodal-no-no-no-no-lru_sharp_max-2core binary...
Running bimodal-no-no-no-no-ship-2core binary...
Running bimodal-no-no-no-no-srrip-2core binary...
```

## The Need

Cache-based side channel attacks manifest due to the exploitation of a inclusive, shared cache in hyper-threading (SMT) environments where the attacker and victim process are executing simultaneously, possibly on two different threads running on two different cores. For example, in evict+reload attack, the spy repeatedly evicts and then reloads a probe address, checking if the victim has accessed the address in between the two operations (See figure below). If victim process did query the address when the spy reloads, it experiences a cache-hit (which can be measured as a reduced memory latency), else it receives a cache miss. With this phenomenon, the attacker process (the spy) can deduce the memory access patterns of the victim process. Note that the probe addresses (addresses whose access patterns can leak information about the victim's program) are identified in an *offline-phase* using automatic tools or with manual effort. The victim program could be any encryption algorithm like RSA, etc.

![Evict+reload attack example](https://github.com/layman-n-ish/TheGuardian/blob/master/imgs/evict_reload.png)

Once we realize the capability of the spy process to evict probe addresses from the private caches of the victim process due to the inclusive nature of the shared cache (usually the LLC), all we have to do to mitigate such attacks is to **minimize the probability of selecting an *inclusion victim* that is being used in the private cache**. Inclusion victims are lines that need to be evicted from a private cache because they are being displaced from the shared cache (by the spy) due to conflicts there (since inclusive replacement policy). 

See ['Acknowledments'](#Acknowledgements) section to discover resources for a deeper understanding.

## Implementation Details

#### Inclusive Caches in ChampSim
Since ChampSim does not implement the inclusive replacement policy inherently, the inclusive replacement policy is implemented for the caches in ChampSim in [`CACHE::handle_fill()`](https://github.com/layman-n-ish/TheGuardian/blob/master/src/cache.cc#L7) method. When a *fill* request is to entertained at the LLC level, the underlying LLC replacement policy is equipped to find a victim way to complete the `handle_fill()` transaction for the recent entry in MSHR (Miss Status Holding Registers); given by `MSHR.next_fill_index`. If the victim block is valid at the LLC level (i.e. valid bit of that block is set), when it's evicted to accomodate a new entry, we'd have to send a back-invalidation request (unset the valid bit, essentially evicting that block) to the upper-level caches if the concerned block is present in the upper-level caches. The same startergy is replicated if the *fill* request comes at the L2C level. 

Check out [this commit](https://github.com/layman-n-ish/TheGuardian/commit/77081fdfbed7a1f611ae1923560359fcba0c5d91#) for the implementation. The whole implementation is guarded by `#ifdef` protections. So, to purge the inclusiveness of the caches, simply comment/remove the line which defines the [`INCLUSIVE_CACHE` macro](https://github.com/layman-n-ish/TheGuardian/blob/master/inc/champsim.h#L28).

Metrics to quantify the inclusiveness of caches were [added](https://github.com/layman-n-ish/TheGuardian/blob/master/inc/ooo_cpu.h#L95) - `L1_backreq_counter`, `L2_backreq_counter`, `LLC_eviction_counter` - these are printed along with the rest of the simulation statistics after the run on ChampSim.

#### Hello, SHARP!

lorem ipsum

## Results and Analysis

Tests were concluded with various variable attributes such as `N_CORES`, `N_SIM_INSTR`, `N_LLC_SETS`, etc. The extracted results can be found in the [`benchmarks/*`](https://github.com/layman-n-ish/TheGuardian/tree/master/benchmarks) directory. The tests were executed on ['dpc3' traces](https://dpc3.compas.cs.stonybrook.edu/?SW_IS) viz. **bwaves_98B.trace.xz**, **gamess_196B.trace.xz**, **gcc_39B.trace.xz** and **libquantum_964B.trace.xz**. 

Some insights we gained were:

- To show our implementaion of SHARP to mitigate cache side channel attacks works, we introduced a metric, [`cross_core_evict_counter`](https://github.com/layman-n-ish/TheGuardian/blob/master/inc/ooo_cpu.h#L95), which accumulates the number of cross-core evictions (inclusion victims). Our goal is, then, simply to show that it converges to zero (ideally), which can be seen in any of the `benchmarks/lru_sharp-*` results. A snippet of [`benchmarks/lru_sharp-2core-30M-2048sets-16ways`](https://github.com/layman-n-ish/TheGuardian/blob/master/benchmarks/lru_sharp-2core-30M-2048sets-16ways) highlighting that is shown below:

```
Back-invalidation requests for CPU 0
	#evictions in LLC: 20798
	#cross-core evictions: 0
	#back-invalidation requests in L2: 13964
	#back-invalidation requests in L1: 1101
Back-invalidation requests for CPU 1
	#evictions in LLC: 925295
	#cross-core evictions: 0
	#back-invalidation requests in L2: 0
	#back-invalidation requests in L1: 0
```
whereas the original implementation of LRU had plenty cross-core evictions seen below in the result snippet of [`benchmarks/lru-2core-30M-2048sets-16ways`](https://github.com/layman-n-ish/TheGuardian/blob/master/benchmarks/lru-2core-30M-2048sets-16ways):

```
Back-invalidation requests for CPU 0
	#evictions in LLC: 28702
	#cross-core evictions: 0
	#back-invalidation requests in L2: 28144
	#back-invalidation requests in L1: 9216
Back-invalidation requests for CPU 1
	#evictions in LLC: 925224
	#cross-core evictions: 27013
	#back-invalidation requests in L2: 0
	#back-invalidation requests in L1: 0
```

- Performace gain is noticed by applying the modified replacement policy (LRU-SHARP) as the [IPC](https://en.wikipedia.org/wiki/Instructions_per_cycle) (Instructions per Cycle) increases.

- Back-invalidation requests & evictions in LLC increases as number of simulation instructions (`N_SIM_INSTR`) increases.

## Acknowledgements

- The project idea is borrowed from a [programming assignment](https://docs.google.com/document/d/1T8I71dl9g2rJuZk9KoHyFuam4dPtuy8Ya6-f64nujIk/edit) issued by Prof. Biswa, IITK, under CS665 - Secure Memory Systems (Fall 2018).

- The replacement algorithm to protect against conflict-based cache side channel attack is adopted from the technical paper on '[Mitigation Secure Hierarchy-Aware Cache Replacement Policy (SHARP)](https://iacoma.cs.uiuc.edu/iacoma-papers/isca17_2.pdf)'
