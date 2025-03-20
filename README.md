# wisp-server-julia
Another wisp server in an obscure language! How spectacular!
**DO NOT USE ON PROD**

Another port of wisp server to a semi obscure language, Unbenchmarked because I coudnt get wispmark to behave with this thing even after modify it a lot (wispmark sucks) but julia is decently fast for A JIT language, Close to C++ speeds with a ruby,python ish syntax. Pretty cool since it can also natively run on GPUs (not this wisp server but julia code in general) its a fun language dispite it mainly being used for math and statistcs its very general purpose too and very easy to scale since its incredibly simple to distribute compute with it.

Usage:
`install julia https://julialang.org/downloads/`
`~>` `julia wisp.jl`
`runs by default on 127.0.0.1:6001/wisp/`

Takeaways:
- Another goofy wisp server
- Dont use in prod, cannot guarentee it wont blow up over something
- It *works*, made with the help of claude because with proper prompting AI can port wisp to almost any language and I dont know julia well enough quite yet to do it all by my self
- Made for fun, probably wont ever recive an update.
