import Foundation

/// StyleSpec + Brief → 模型专用提示词。纯函数，无网络无 IO。
///
/// 模型只是可替换的生成出口，新增模型 = 新增一个适配器，不动 StyleSpec。
public enum Compiler {

    public static func compile(_ spec: StyleSpec, _ brief: Brief, model: ModelId) throws
        -> CompiledPrompt
    {
        switch model {
        case .jimeng:
            return JimengAdapter.compile(spec, brief)
        case .gptImage:
            return try GPTImageAdapter.compile(spec, brief)
        }
    }

    /// 一次编译全部模型。某个适配器抛错不影响其他的——
    /// 边界四纪律不齐只该拦下 GPT Image 的编辑指令，不该连即梦的文生图一起废掉。
    public static func compileAll(_ spec: StyleSpec, _ brief: Brief)
        -> [(model: ModelId, result: Result<CompiledPrompt, CompileError>)]
    {
        ModelId.allCases.map { model in
            do {
                return (model, .success(try compile(spec, brief, model: model)))
            } catch let error as CompileError {
                return (model, .failure(error))
            } catch {
                return (
                    model,
                    .failure(CompileError(rule: "unknown", message: error.localizedDescription))
                )
            }
        }
    }
}
