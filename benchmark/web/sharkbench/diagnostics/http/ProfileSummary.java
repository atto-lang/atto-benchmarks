import java.nio.file.Path;
import java.util.*;
import jdk.jfr.consumer.*;

/** Sample attribution, not exact CPU time or allocation totals. */
class ProfileSummary {
    static void add(Map<String, Long> m, String key, long value) {
        m.merge(key, value, Math::addExact);
    }
    static String frame(RecordedFrame f) {
        return f.getMethod().getType().getName()+"."+f.getMethod().getName();
    }
    static void top(String name, Map<String, Long> m) {
        System.out.println(name);
        m.entrySet().stream().sorted(Map.Entry.<String, Long>comparingByValue().reversed()
                .thenComparing(Map.Entry.comparingByKey())).limit(30)
                .forEach(e -> System.out.println(e.getValue()+" "+e.getKey()));
    }
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("recording required");
        long cpu=0, alloc=0, weight=0, attributedCpu=0, attributedAlloc=0;
        Map<String,Long> cpuLeaf=new HashMap<>(), cpuAtto=new HashMap<>(),
                allocTypes=new HashMap<>(), allocAtto=new HashMap<>();
        try (var recording=new RecordingFile(Path.of(args[0]))) {
            while(recording.hasMoreEvents()) {
                var event=recording.readEvent();
                String kind=event.getEventType().getName();
                boolean execution=kind.equals("jdk.ExecutionSample");
                boolean allocation=kind.equals("jdk.ObjectAllocationSample");
                if (!execution && !allocation) continue;
                long w=execution?1:event.getLong("weight");
                if(w<=0) throw new IllegalStateException("invalid sample weight");
                if(execution) cpu++; else {
                    alloc++;
                    weight=Math.addExact(weight,w);
                    add(allocTypes,event.getClass("objectClass").getName(),w);
                }
                var trace=event.getStackTrace();
                if(trace==null || trace.getFrames().isEmpty()) continue;
                var frames=trace.getFrames();
                if(execution) add(cpuLeaf,frame(frames.getFirst()),1);
                // First Atto frame attributes once per sample; avoid double counting callers.
                for(var f:frames) {
                    String method=frame(f);
                    if(method.startsWith("dev.oreslang.")) {
                        if(execution) { add(cpuAtto,method,1); attributedCpu++; }
                        else { add(allocAtto,method,w); attributedAlloc++; }
                        break;
                    }
                }
            }
        }
        System.out.printf("CPU_SAMPLES=%d ALLOCATION_SAMPLES=%d ALLOCATION_SAMPLE_WEIGHT_BYTES=%d ATTO_CPU_SAMPLES=%d ATTO_ALLOCATION_SAMPLES=%d%n",
                cpu,alloc,weight,attributedCpu,attributedAlloc);
        if(cpu==0 || alloc==0 || attributedCpu==0 || attributedAlloc==0)
            throw new IllegalStateException("missing usable CPU or allocation samples");
        top("CPU_LEAF_SAMPLE_COUNTS",cpuLeaf);
        top("CPU_FIRST_ATTO_FRAME_SAMPLE_COUNTS",cpuAtto);
        top("ALLOCATION_TYPE_SAMPLE_WEIGHT_BYTES",allocTypes);
        top("ALLOCATION_FIRST_ATTO_FRAME_SAMPLE_WEIGHT_BYTES",allocAtto);
    }
}
