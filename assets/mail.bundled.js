// deno-fmt-ignore-file
// deno-lint-ignore-file
// This code was bundled using `deno bundle` and it's not recommended to edit it manually

class ThreadList {
    constructor(root, selected){
        this.root = root;
        root.addEventListener('click', (event)=>{
            const row = event.target.closest('[data-thread]');
            if (row) selected.notify(row.dataset.thread);
        });
        selected.on((id)=>{
            this.mark(id);
        });
    }
    mark(id) {
        for (const row of this.root.querySelectorAll('.bm-thread.bm-active')){
            row.classList.remove('bm-active');
        }
        const row = this.root.querySelector(`[data-thread="${CSS.escape(id)}"]`);
        if (row) row.classList.add('bm-active');
    }
}
function fitFrame(frame) {
    const fit = ()=>{
        const doc = frame.contentDocument;
        if (!doc || !doc.body) return;
        const height = Math.max(doc.documentElement.offsetHeight, doc.body.scrollHeight);
        frame.style.height = height + 'px';
    };
    const watch = ()=>{
        fit();
        if (frame.contentDocument?.body) new ResizeObserver(fit).observe(frame.contentDocument.body);
    };
    frame.addEventListener('load', watch);
    if (frame.contentDocument?.readyState === 'complete') watch();
    new ResizeObserver(fit).observe(frame);
}
export { ThreadList as ThreadList };
export { fitFrame as fitFrame };
