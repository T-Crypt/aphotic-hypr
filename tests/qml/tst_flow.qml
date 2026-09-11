import QtQuick
import QtTest
import "../../Configs/quickshell/aphotic/modules/flow"
import "../../Configs/quickshell/aphotic/modules/flow/FlowModel.js" as Model

TestCase {
    id: test
    name: "AphoticFlow"
    when: windowShown
    visible: true
    width: 940; height: 620
    FlowScene { id: scene; width: 940; height: 620 }
    SignalSpy { id: decision; target: scene; signalName: "decide" }
    function init() {
        scene.visible = true;
        scene.motion = true;
        scene.flow = Model.build([{id:'a',owner:'gaming',resource:'cpu',amount:3,priority:'foreground',origin:'dynamic',label:'Game'}], {cpu:{capacity:8,safetyMargin:0.1,unit:'cores'}}, {}, {});
        scene.pending = {id:7,resourceLabel:'CPU',claimant:{owner:'ai'},requestor:{owner:'gaming'},claimantSuspendable:false};
        decision.clear();
        wait(20);
    }
    function test_select_resource() {
        mouseClick(findChild(scene,'resource-cpu'));
        compare(scene.selected.key,'cpu');
        compare(scene.selected.claims[0].unit,'cores');
    }
    function test_select_workload() {
        mouseClick(findChild(scene,'workload-gaming'));
        compare(scene.selectionKind,'workload');
        compare(scene.selected.key,'gaming');
    }
    function test_unstoppable_disabled() {
        const action = findChild(scene,'suspendAction');
        compare(action.enabled,false);
        mouseClick(action);
        compare(decision.count,0);
    }
    function test_keep_emits_current_id() {
        mouseClick(findChild(scene,'keepAction'));
        compare(decision.count,1);
        compare(decision.signalArguments[0][0],7);
        compare(decision.signalArguments[0][1],'keep');
    }
    function test_queue_replacement_during_press() {
        const action = findChild(scene,'keepAction');
        mousePress(action);
        scene.pending = {id:8,resourceLabel:'CPU',claimant:{owner:'security'},requestor:{owner:'dev'},claimantSuspendable:true};
        mouseRelease(action);
        compare(decision.count,0);
    }
    function test_hidden_stops_motion() {
        scene.visible = false;
        compare(findChild(scene,'flowPulse').running,false);
    }
    function test_motion_toggle_stops_motion() {
        scene.motion = false;
        compare(findChild(scene,'flowPulse').running,false);
    }
    function test_select_plane() {
        mouseClick(findChild(scene,'plane-gaming'));
        compare(scene.selectionKind,'plane');
        compare(scene.selected.key,'gaming');
        compare(scene.selected.claims.length,1);
        verify(scene.selected.detail.indexOf('1 claim held') >= 0);
    }
    function test_uninstalled_plane_not_selectable() {
        scene.selectionKind = 'resource';
        scene.selectionKey = 'cpu';
        scene.flow = Model.build([], {cpu:{capacity:8,safetyMargin:0.1,unit:'cores'}}, {}, {}, {ai:true,gaming:false,security:true,dev:true});
        const chip = findChild(scene,'plane-gaming');
        compare(chip.enabled,false);
        mouseClick(chip);
        compare(scene.selectionKind,'resource');
    }
    function test_settled_map_does_not_replay_pulse() {
        const claims = [{id:'a',owner:'gaming',resource:'cpu',amount:3,priority:'foreground',origin:'dynamic',label:'Game'}];
        const specs = {cpu:{capacity:8,safetyMargin:0.1,unit:'cores'}};
        tryCompare(findChild(scene,'flowPulse'),'running',false,2000);
        scene.flow = Model.build(claims, specs, {}, {});
        compare(findChild(scene,'flowPulse').running,false);
    }
    function test_metric_delegates_survive_a_value_tick() {
        scene.metrics = [{label:'CPU',value:'10%'},{label:'GPU',value:'4%'}];
        wait(20);
        const first = findChild(scene,'metric-0');
        scene.metrics = [{label:'CPU',value:'11%'},{label:'GPU',value:'5%'}];
        wait(20);
        compare(findChild(scene,'metric-0'),first);
        compare(first.modelData.value,'11%');
    }
    function test_empty_state() {
        scene.flow = Model.build([],{}, {},{});
        scene.pending = null;
        compare(scene.flow.workloads.length,0);
        compare(scene.flow.planes.length,4);
        compare(scene.flow.planes.filter(p => p.active).length,0);
    }
    function test_contention_preview_is_a_projection() {
        const negotiation = {id:9,resource:'cpu',resourceLabel:'CPU',unit:'cores',total:9,budget:7.2,
            claimant:{owner:'ai',amount:6},requestor:{owner:'gaming',amount:3},claimantSuspendable:true};
        scene.pending = negotiation;
        scene.projection = Model.projection(negotiation, [{owner:'ai',resource:'cpu',amount:6}]);
        wait(20);
        const preview = findChild(scene,'contentionPreview');
        compare(preview.visible,true);
        verify(preview.text.indexOf('Projection') === 0);
        verify(preview.text.indexOf('6 cores') > 0);
        verify(preview.text.indexOf('Nothing changes until you choose') > 0);
        compare(decision.count,0);
    }
    function test_preview_hidden_without_a_negotiation() {
        scene.pending = null;
        scene.projection = null;
        wait(20);
        compare(findChild(scene,'contentionPreview').visible,false);
    }
    function test_receipt_lens_does_not_promote_a_request() {
        scene.flow = Model.build([], {cpu:{capacity:8,safetyMargin:0.1,unit:'cores'}}, {}, {}, {},
            [{token:'w1',plane:'ai',owner:'ai',label:'llama',trigger:'model-resident',status:'stale',claims:[]}],
            [{id:'r1',profileId:'ai',kind:'model-unload',status:'requested',requestedAt:0}]);
        wait(20);
        mouseClick(findChild(scene,'workload-ai'));
        compare(scene.selectedReceipts.length,1);
        compare(scene.selectedReceipts[0].statusLabel,'Requested');
        compare(scene.selectedWork[0].stale,true);
        verify(scene.selectedWork[0].detail.indexOf('source went quiet') > 0);
        verify(findChild(scene,'exportReceiptsAction').visible);
    }
    function test_shell_activity_is_opt_in_and_not_a_claim() {
        const shell = {enabled:true, ready:true, cpuPerc:0.031, cores:1, memoryMib:480};
        scene.flow = Model.build([{id:'a',owner:'gaming',resource:'cpu',amount:3,priority:'foreground',origin:'dynamic',label:'Game'}],
            {cpu:{capacity:8,safetyMargin:0.1,unit:'cores'}}, {}, {}, {}, [], [], shell);
        scene.shellActivity = true;
        wait(20);
        const node = findChild(scene,'workload-__shell');
        verify(node);
        verify(node.text.indexOf('Aphotic shell') > 0);
        mouseClick(node);
        compare(scene.selected.key,'__shell');
        compare(scene.selected.claims.length,0);
        compare(scene.flow.claimCount,1);
        verify(scene.selected.detail.indexOf('never arbitrated') > 0);
        compare(findChild(scene,'shellActivityAction').chosen,true);
    }
    function test_shell_activity_off_leaves_no_node() {
        scene.shellActivity = false;
        scene.flow = Model.build([], {cpu:{capacity:8,safetyMargin:0.1,unit:'cores'}}, {}, {}, {}, [], [], {enabled:false});
        wait(20);
        compare(findChild(scene,'workload-__shell'), null);
        compare(findChild(scene,'shellActivityAction').chosen,false);
    }
    function test_shell_activity_button_asks_rather_than_assumes() {
        const spy = Qt.createQmlObject('import QtTest; SignalSpy {}', test);
        spy.target = scene;
        spy.signalName = 'shellActivityToggled';
        scene.shellActivity = false;
        wait(20);
        mouseClick(findChild(scene,'shellActivityAction'));
        compare(spy.count,1);
        compare(scene.shellActivity,false,'the view does not flip itself; the setting owns the state');
    }
}
